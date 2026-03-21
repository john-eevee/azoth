use std::cell::RefCell;
use std::collections::BTreeMap;
use std::collections::HashSet;

use crate::channel_ref::ChannelRef;
use anyhow::anyhow;
use starlark::any::ProvidesStaticType;
use starlark::environment::GlobalsBuilder;
use starlark::environment::Module;
use starlark::eval::Evaluator;
use starlark::starlark_module;
use starlark::syntax::AstModule;
use starlark::syntax::Dialect;
use starlark::values::dict::DictRef;
use starlark::values::float::StarlarkFloat;
use starlark::values::list::ListRef;
use starlark::values::none::NoneType;
use starlark::values::UnpackValue;
use starlark::values::Value;
use starlark::values::ValueLike;

use crate::error::ValidationError;
use crate::error::ValidationErrors;
use crate::ir::ChannelDef;
use crate::ir::ChannelSource;
use crate::ir::ChannelType;
use crate::ir::ImageDef;
use crate::ir::OutputDef;
use crate::ir::ProcessDescriptor;
use crate::ir::ResourceDef;
use crate::ir::WorkflowPlan;

const MAX_NAME_LEN: usize = 120;

/// Returns `Ok(())` if `name` matches `[a-zA-Z0-9_.]{1,120}`, else an error.
fn validate_name(name: &str, context: &str) -> anyhow::Result<()> {
    if name.is_empty() {
        return Err(anyhow!("{context}: name must not be empty"));
    }
    if name.len() > MAX_NAME_LEN {
        return Err(anyhow!(
            "{context}: name '{}' exceeds {MAX_NAME_LEN} characters",
            name
        ));
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.')
    {
        return Err(anyhow!(
            "{context}: name '{name}' contains invalid characters \
             (allowed: [a-zA-Z0-9_.])"
        ));
    }
    Ok(())
}

/// Shared mutable state injected via `eval.extra` to capture what the DSL emits.
#[derive(Debug, Default, ProvidesStaticType)]
struct ParseOutput {
    processes: RefCell<Vec<ProcessDescriptor>>,
    channels: RefCell<Vec<ChannelDef>>,
    workflow_name: RefCell<Option<String>>,
    /// Monotonic counter for synthetic IDs.
    counter: RefCell<u32>,
}

impl ParseOutput {
    fn next_id(&self) -> String {
        let mut c = self.counter.borrow_mut();
        let id = format!("id_{c}");
        *c += 1;
        id
    }
}

#[starlark_module]
fn starlark_process(builder: &mut GlobalsBuilder) {
    fn process<'v>(
        #[starlark(kwargs)] kwargs: DictRef<'v>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<Value<'v>> {
        let output = extra(eval)?;
        let process_id = output.next_id();

        // Resolve process name: explicit `name=` kwarg takes precedence;
        // fall back to the enclosing Starlark function name from the call stack.
        let name = resolve_process_name(&kwargs, eval)?;

        let desc = extract_process(process_id.clone(), name, &kwargs)?;
        output.processes.borrow_mut().push(desc);

        // A process creates an implicit Result channel representing its outputs
        let channel_id = format!("chan_{}", process_id);
        output.channels.borrow_mut().push(ChannelDef {
            id: channel_id.clone(),
            channel_type: ChannelType::Result,
            source: ChannelSource::Result { process_id },
        });

        Ok(eval.heap().alloc(ChannelRef { id: channel_id }))
    }
}

#[starlark_module]
fn starlark_channel(builder: &mut GlobalsBuilder) {
    fn channel_from_path<'v>(
        glob: &str,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<Value<'v>> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id: id.clone(),
            channel_type: ChannelType::Path,
            source: ChannelSource::FromPath {
                glob: glob.to_owned(),
            },
        });
        Ok(eval.heap().alloc(ChannelRef { id }))
    }

    fn channel_literal<'v>(
        value: &str,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<Value<'v>> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id: id.clone(),
            channel_type: ChannelType::Literal,
            source: ChannelSource::Literal {
                value: value.to_owned(),
            },
        });
        Ok(eval.heap().alloc(ChannelRef { id }))
    }

    fn channel_join<'v>(
        _args: Value<'v>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<Value<'v>> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id: id.clone(),
            channel_type: ChannelType::Result,
            source: ChannelSource::Result {
                process_id: format!("join_{id}"),
            },
        });
        Ok(eval.heap().alloc(ChannelRef { id }))
    }
}

#[starlark_module]
fn starlark_workflow(builder: &mut GlobalsBuilder) {
    fn workflow<'v>(
        #[starlark(kwargs)] kwargs: DictRef<'v>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let output = extra(eval)?;
        let name = kwargs
            .get_str("name")
            .and_then(|v| v.unpack_str().map(str::to_owned))
            .ok_or_else(|| anyhow!("workflow() missing 'name'"))?;
        *output.workflow_name.borrow_mut() = Some(name);

        if kwargs.get_str("channels").is_some() || kwargs.get_str("processes").is_some() {
            return Err(anyhow!("workflow() should not take 'channels' or 'processes'. Pass channels between processes and use `target=` to specify the final output."));
        }

        Ok(NoneType)
    }
}

fn extra<'v, 'a>(eval: &'a Evaluator<'v, '_, '_>) -> anyhow::Result<&'a ParseOutput> {
    eval.extra
        .ok_or_else(|| anyhow!("eval.extra not set"))?
        .downcast_ref::<ParseOutput>()
        .ok_or_else(|| anyhow!("eval.extra wrong type"))
}

/// Resolve the name for a `process()` call.
///
/// Priority:
/// 1. Explicit `name=` kwarg in `process()`.
/// 2. The name of the innermost non-`main` user function on the call stack
///    (i.e. the DSL function that called `process()`).
///
/// Returns an error if neither source yields a valid name, or if the name
/// fails format validation.
fn resolve_process_name(
    kwargs: &DictRef<'_>,
    eval: &Evaluator<'_, '_, '_>,
) -> anyhow::Result<String> {
    // 1. Explicit kwarg takes precedence.
    if let Some(v) = kwargs.get_str("name") {
        let name = v
            .unpack_str()
            .ok_or_else(|| anyhow!("process(): 'name' must be a string"))?
            .to_owned();
        validate_name(&name, "process(name=...)")?;
        return Ok(name);
    }

    // 2. Walk the call stack from top (innermost) to find the first user
    //    function that is not `main` or the `process` builtin itself.
    //    The call stack from the starlark crate is ordered outermost-first,
    //    so we reverse it.
    //
    //    Frames for Rust builtins have `location == None`; we skip those.
    //    We also skip `main` (the workflow entry point) and `process` (the
    //    NIF builtin whose frame sits innermost on the stack).
    let frames = eval.call_stack().into_frames();
    let name = frames
        .iter()
        .rev()
        .filter(|f| f.location.is_some() && f.name != "main" && f.name != "process")
        .map(|f| f.name.clone())
        .next()
        .ok_or_else(|| {
            anyhow!(
                "process() called outside a named function — \
                 add an explicit name= kwarg or wrap in a def"
            )
        })?;

    validate_name(&name, &format!("function '{name}'"))?;
    Ok(name)
}

fn extract_process(
    id: String,
    name: String,
    kwargs: &DictRef<'_>,
) -> anyhow::Result<ProcessDescriptor> {
    let image = extract_image(kwargs, &name)?;
    let command = require_str(kwargs, "command", &name)?;
    let inputs = extract_inputs(kwargs, &name)?;
    let outputs = extract_outputs(kwargs, &name)?;
    let resources = extract_resources(kwargs, &name)?;
    let retry = extract_retry(kwargs, &name)?;

    Ok(ProcessDescriptor {
        id,
        name,
        image,
        command,
        inputs,
        outputs,
        resources,
        retry,
    })
}

fn extract_retry(kwargs: &DictRef<'_>, proc_name: &str) -> anyhow::Result<Option<RetryDef>> {
    let val = match kwargs.get_str("retry") {
        Some(v) => v,
        None => return Ok(None),
    };

    let dict = DictRef::from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry' must be a dict"))?;

    let backoff = dict
        .get_str("backoff")
        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry' dict missing 'backoff'"))?
        .unpack_str()
        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry.backoff' must be a string"))?;

    let count = dict
        .get_str("count")
        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry' dict missing 'count'"))?
        .unpack_i32()
        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry.count' must be an integer"))?
        as u32;

    match backoff {
        "exponential" => {
            let exponent = dict
                .get_str("exponent")
                .ok_or_else(|| {
                    anyhow!("process '{proc_name}': 'retry' exponential backoff missing 'exponent'")
                })?;
            let exponent = num_from_value(exponent).ok_or_else(|| {
                anyhow!("process '{proc_name}': 'retry.exponent' must be a number")
            })?;

            let initial_delay = dict
                .get_str("initial_delay")
                .map(num_from_value)
                .flatten()
                .map(|f| f as u32)
                .unwrap_or(500);

            Ok(Some(RetryDef::Exponential {
                count,
                exponent,
                initial_delay,
            }))
        }
        "linear" => {
            let delays_val = dict.get_str("delays").ok_or_else(|| {
                anyhow!("process '{proc_name}': 'retry' linear backoff missing 'delays'")
            })?;

            let list = ListRef::from_value(delays_val).ok_or_else(|| {
                anyhow!("process '{proc_name}': 'retry.delays' must be a list")
            })?;

            let mut delays: Vec<u32> = list
                .iter()
                .map(|v| {
                    v.unpack_i32()
                        .map(|i| i as u32)
                        .ok_or_else(|| anyhow!("process '{proc_name}': 'retry.delays' item must be an integer"))
                })
                .collect::<anyhow::Result<Vec<_>>>()?;

            if delays.is_empty() {
                return Err(anyhow!(
                    "process '{proc_name}': 'retry.delays' must not be empty"
                ));
            }

            // Pad or truncate delays to match count
            if delays.len() < count as usize {
                let last = *delays.last().unwrap();
                delays.resize(count as usize, last);
            } else if delays.len() > count as usize {
                delays.truncate(count as usize);
            }

            Ok(Some(RetryDef::Linear { count, delays }))
        }
        _ => Err(anyhow!(
            "process '{proc_name}': invalid retry backoff '{}' (expected 'exponential' or 'linear')",
            backoff
        )),
    }
}

fn extract_image(kwargs: &DictRef<'_>, proc_name: &str) -> anyhow::Result<ImageDef> {
    let val = kwargs
        .get_str("image")
        .ok_or_else(|| anyhow!("process '{proc_name}': missing 'image'"))?;

    // Fast path: string literal
    if let Some(s) = val.unpack_str() {
        return Ok(ImageDef {
            tag: s.to_owned(),
            checksum: None,
        });
    }

    // Object/Dict form: { "tag": "...", "checksum": "..." }
    if let Some(dict) = DictRef::from_value(val) {
        let tag = dict
            .get_str("tag")
            .ok_or_else(|| anyhow!("process '{proc_name}': 'image' dict missing 'tag'"))?
            .unpack_str()
            .ok_or_else(|| anyhow!("process '{proc_name}': 'image.tag' must be a string"))?
            .to_owned();

        let checksum = dict
            .get_str("checksum")
            .map(|v| {
                v.unpack_str()
                    .ok_or_else(|| {
                        anyhow!("process '{proc_name}': 'image.checksum' must be a string")
                    })
                    .map(str::to_owned)
            })
            .transpose()?;

        return Ok(ImageDef { tag, checksum });
    }

    Err(anyhow!(
        "process '{proc_name}': 'image' must be a string or a dict"
    ))
}

fn require_str(kwargs: &DictRef<'_>, key: &str, proc_name: &str) -> anyhow::Result<String> {
    kwargs
        .get_str(key)
        .and_then(|v| v.unpack_str().map(str::to_owned))
        .ok_or_else(|| anyhow!("process '{proc_name}': missing or non-string field '{key}'"))
}

fn extract_inputs(
    kwargs: &DictRef<'_>,
    proc_name: &str,
) -> anyhow::Result<BTreeMap<String, String>> {
    let val = kwargs
        .get_str("inputs")
        .ok_or_else(|| anyhow!("process '{proc_name}': missing 'inputs'"))?;

    let dict = DictRef::from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_name}': 'inputs' must be a dict"))?;

    let mut map = BTreeMap::new();
    for (k, v) in dict.iter() {
        let key = k
            .unpack_str()
            .ok_or_else(|| anyhow!("process '{proc_name}': input key must be a string"))?
            .to_owned();

        if let Some(chan) = v.downcast_ref::<ChannelRef>() {
            map.insert(key, chan.id.clone());
        } else {
            return Err(anyhow!(
                "process '{proc_name}': input '{key}' must be a channel (use channel_literal or pass the output of a process)"
            ));
        }
    }
    Ok(map)
}

fn extract_outputs(kwargs: &DictRef<'_>, proc_name: &str) -> anyhow::Result<OutputDef> {
    let val = kwargs
        .get_str("outputs")
        .ok_or_else(|| anyhow!("process '{proc_name}': missing 'outputs'"))?;

    if let Some(dict) = DictRef::from_value(val) {
        let mut map = BTreeMap::new();
        for (k, v) in dict.iter() {
            let key = k
                .unpack_str()
                .ok_or_else(|| anyhow!("process '{proc_name}': output key must be a string"))?
                .to_owned();
            let uri = v
                .unpack_str()
                .ok_or_else(|| {
                    anyhow!("process '{proc_name}': output '{key}' must be a string URI")
                })?
                .to_owned();
            map.insert(key, uri);
        }
        return Ok(OutputDef::Static(map));
    }

    if let Some(list) = ListRef::from_value(val) {
        let globs = list
            .iter()
            .map(|v| {
                v.unpack_str()
                    .map(str::to_owned)
                    .ok_or_else(|| anyhow!("process '{proc_name}': glob pattern must be a string"))
            })
            .collect::<anyhow::Result<Vec<_>>>()?;
        return Ok(OutputDef::Glob(globs));
    }

    Err(anyhow!(
        "process '{proc_name}': 'outputs' must be a dict or list"
    ))
}

fn extract_resources(kwargs: &DictRef<'_>, proc_name: &str) -> anyhow::Result<ResourceDef> {
    let val = kwargs
        .get_str("resources")
        .ok_or_else(|| anyhow!("process '{proc_name}': missing 'resources'"))?;

    let dict = DictRef::from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_name}': 'resources' must be a dict"))?;

    let cpu = extract_num_from_dict(&dict, "cpu", proc_name)?;
    let mem = extract_num_from_dict(&dict, "mem", proc_name)?;
    let disk = extract_num_from_dict(&dict, "disk", proc_name)?;

    Ok(ResourceDef { cpu, mem, disk })
}

/// Extract a numeric value (int or float) from a DictRef.
fn extract_num_from_dict(dict: &DictRef<'_>, key: &str, proc_name: &str) -> anyhow::Result<f64> {
    let val = dict
        .get_str(key)
        .ok_or_else(|| anyhow!("process '{proc_name}': resource '{key}' missing"))?;

    num_from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_name}': resource '{key}' must be a number"))
}

fn num_from_value(val: Value<'_>) -> Option<f64> {
    // Fast path: plain integer.
    if let Some(i) = val.unpack_i32() {
        return Some(i as f64);
    }
    // Slow path: float via StarlarkFloat (implements public UnpackValue).
    StarlarkFloat::unpack_value(val).ok().flatten().map(|f| f.0)
}

/// Parse Starlark DSL source and return a [`WorkflowPlan`].
pub fn parse(source: &str) -> Result<WorkflowPlan, ValidationError> {
    let ast =
        AstModule::parse("workflow.star", source.to_owned(), &Dialect::Standard).map_err(|e| {
            ValidationError::StarlarkError {
                message: e.to_string(),
            }
        })?;

    let globals = GlobalsBuilder::new()
        .with(starlark_process)
        .with(starlark_channel)
        .with(starlark_workflow)
        .build();

    let module = Module::new();
    let output = ParseOutput::default();

    // Evaluate module-level definitions (def align, def main, etc.) and then
    // call main() — all inside one evaluator so Value lifetimes are consistent.
    {
        let mut eval = Evaluator::new(&module);
        eval.extra = Some(&output);
        eval.eval_module(ast, &globals)
            .map_err(|e| ValidationError::StarlarkError {
                message: e.to_string(),
            })?;

        let main_fn = module.get("main").ok_or(ValidationError::NoWorkflowFound)?;

        eval.eval_function(main_fn, &[], &[])
            .map_err(|e| ValidationError::StarlarkError {
                message: e.to_string(),
            })?;
    }

    let name = output
        .workflow_name
        .borrow()
        .clone()
        .ok_or(ValidationError::NoWorkflowFound)?;

    let processes = output.processes.into_inner();

    // Reject workflows where two processes share the same name — names must be
    // unique within a workflow so the registry lookup is unambiguous.
    let mut seen: HashSet<&str> = HashSet::new();
    for proc in &processes {
        if !seen.insert(proc.name.as_str()) {
            return Err(ValidationError::DuplicateProcessName {
                workflow_name: name.clone(),
                name: proc.name.clone(),
            });
        }
    }

    Ok(WorkflowPlan {
        version: 1,
        name,
        processes,
        channels: output.channels.into_inner(),
    })
}
