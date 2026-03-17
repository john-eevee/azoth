use std::cell::RefCell;
use std::collections::BTreeMap;

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

use crate::error::ValidationError;
use crate::ir::ChannelDef;
use crate::ir::ChannelSource;
use crate::ir::ChannelType;
use crate::ir::OutputDef;
use crate::ir::ProcessDescriptor;
use crate::ir::ResourceDef;
use crate::ir::WorkflowPlan;

// ── Captured output ──────────────────────────────────────────────────────────

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

// ── DSL builtins ─────────────────────────────────────────────────────────────

#[starlark_module]
fn starlark_process(builder: &mut GlobalsBuilder) {
    fn process<'v>(
        #[starlark(kwargs)] kwargs: DictRef<'v>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let output = extra(eval)?;
        let process_id = output.next_id();
        let desc = extract_process(process_id, &kwargs)?;
        output.processes.borrow_mut().push(desc);
        Ok(NoneType)
    }
}

#[starlark_module]
fn starlark_channel(builder: &mut GlobalsBuilder) {
    fn channel_from_path<'v>(
        glob: &str,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id,
            channel_type: ChannelType::Path,
            source: ChannelSource::FromPath {
                glob: glob.to_owned(),
            },
        });
        Ok(NoneType)
    }

    fn channel_literal<'v>(
        value: &str,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id,
            channel_type: ChannelType::Literal,
            source: ChannelSource::Literal {
                value: value.to_owned(),
            },
        });
        Ok(NoneType)
    }

    fn channel_join<'v>(
        _args: Value<'v>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let output = extra(eval)?;
        let id = output.next_id();
        output.channels.borrow_mut().push(ChannelDef {
            id: id.clone(),
            channel_type: ChannelType::Result,
            source: ChannelSource::Result {
                process_id: format!("join_{id}"),
            },
        });
        Ok(NoneType)
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
        Ok(NoneType)
    }
}

// ── Extraction helpers ────────────────────────────────────────────────────────

fn extra<'v, 'a>(eval: &'a Evaluator<'v, '_, '_>) -> anyhow::Result<&'a ParseOutput> {
    eval.extra
        .ok_or_else(|| anyhow!("eval.extra not set"))?
        .downcast_ref::<ParseOutput>()
        .ok_or_else(|| anyhow!("eval.extra wrong type"))
}

fn extract_process(id: String, kwargs: &DictRef<'_>) -> anyhow::Result<ProcessDescriptor> {
    let image = require_str(kwargs, "image", &id)?;
    let command = require_str(kwargs, "command", &id)?;
    let inputs = extract_inputs(kwargs, &id)?;
    let outputs = extract_outputs(kwargs, &id)?;
    let resources = extract_resources(kwargs, &id)?;

    Ok(ProcessDescriptor {
        id,
        image,
        command,
        inputs,
        outputs,
        resources,
    })
}

fn require_str(kwargs: &DictRef<'_>, key: &str, proc_id: &str) -> anyhow::Result<String> {
    kwargs
        .get_str(key)
        .and_then(|v| v.unpack_str().map(str::to_owned))
        .ok_or_else(|| anyhow!("process '{proc_id}': missing or non-string field '{key}'"))
}

fn extract_inputs(kwargs: &DictRef<'_>, proc_id: &str) -> anyhow::Result<BTreeMap<String, String>> {
    let val = kwargs
        .get_str("inputs")
        .ok_or_else(|| anyhow!("process '{proc_id}': missing 'inputs'"))?;

    let dict = DictRef::from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_id}': 'inputs' must be a dict"))?;

    let mut map = BTreeMap::new();
    for (k, v) in dict.iter() {
        let key = k
            .unpack_str()
            .ok_or_else(|| anyhow!("process '{proc_id}': input key must be a string"))?
            .to_owned();
        // Input values are channel references at runtime; store their string
        // representation if available, otherwise record the type name.
        let value = v.unpack_str().unwrap_or("").to_owned();
        map.insert(key, value);
    }
    Ok(map)
}

fn extract_outputs(kwargs: &DictRef<'_>, proc_id: &str) -> anyhow::Result<OutputDef> {
    let val = kwargs
        .get_str("outputs")
        .ok_or_else(|| anyhow!("process '{proc_id}': missing 'outputs'"))?;

    if let Some(dict) = DictRef::from_value(val) {
        let mut map = BTreeMap::new();
        for (k, v) in dict.iter() {
            let key = k
                .unpack_str()
                .ok_or_else(|| anyhow!("process '{proc_id}': output key must be a string"))?
                .to_owned();
            let uri = v
                .unpack_str()
                .ok_or_else(|| anyhow!("process '{proc_id}': output '{key}' must be a string URI"))?
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
                    .ok_or_else(|| anyhow!("process '{proc_id}': glob pattern must be a string"))
            })
            .collect::<anyhow::Result<Vec<_>>>()?;
        return Ok(OutputDef::Glob(globs));
    }

    Err(anyhow!(
        "process '{proc_id}': 'outputs' must be a dict or list"
    ))
}

fn extract_resources(kwargs: &DictRef<'_>, proc_id: &str) -> anyhow::Result<ResourceDef> {
    let val = kwargs
        .get_str("resources")
        .ok_or_else(|| anyhow!("process '{proc_id}': missing 'resources'"))?;

    let dict = DictRef::from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_id}': 'resources' must be a dict"))?;

    let cpu = extract_num_from_dict(&dict, "cpu", proc_id)?;
    let mem = extract_num_from_dict(&dict, "mem", proc_id)?;
    let disk = extract_num_from_dict(&dict, "disk", proc_id)?;

    Ok(ResourceDef { cpu, mem, disk })
}

/// Extract a numeric value (int or float) from a DictRef.
fn extract_num_from_dict(dict: &DictRef<'_>, key: &str, proc_id: &str) -> anyhow::Result<f64> {
    let val = dict
        .get_str(key)
        .ok_or_else(|| anyhow!("process '{proc_id}': resource '{key}' missing"))?;

    num_from_value(val)
        .ok_or_else(|| anyhow!("process '{proc_id}': resource '{key}' must be a number"))
}

fn num_from_value(val: Value<'_>) -> Option<f64> {
    // Fast path: plain integer.
    if let Some(i) = val.unpack_i32() {
        return Some(i as f64);
    }
    // Slow path: float via StarlarkFloat (implements public UnpackValue).
    StarlarkFloat::unpack_value(val).ok().flatten().map(|f| f.0)
}

// ── Public parse entry point ──────────────────────────────────────────────────

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

    Ok(WorkflowPlan {
        version: 1,
        name,
        processes: output.processes.into_inner(),
        channels: output.channels.into_inner(),
    })
}
