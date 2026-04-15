use std::collections::{BTreeMap, HashMap, HashSet};

use kdl::KdlDocument;

use crate::error::ValidationError;
use crate::ir::{
    ChannelDef, ChannelSource, ChannelType, ImageDef, InputDef, OutputDef, OutputFileDef,
    ProcessDescriptor, ResourceDef, RetryDef, WorkflowPlan,
};

pub fn parse(source: &str) -> Result<WorkflowPlan, ValidationError> {
    let document = match source.parse::<KdlDocument>() {
        Ok(doc) => doc,
        Err(e) => return Err(ValidationError::InternalParseError { message: e.to_string() }),
    };

    let mut workflow_name = None;
    let mut processes = Vec::new();
    let mut channels = Vec::new();

    for node in document.nodes() {
        if node.name().value() == "workflow" {
            if let Some(name) = node.get(0).and_then(|v| v.as_string()) {
                workflow_name = Some(name.to_string());
            } else if let Some(name) = node.get("name").and_then(|v| v.as_string()) {
                workflow_name = Some(name.to_string());
            }

            if let Some(children) = node.children() {
                for child_node in children.nodes() {
                    match child_node.name().value() {
                        "process" => {
                            let mut name = child_node.get(0).and_then(|v| v.as_string()).unwrap_or("").to_string();
                            if let Some(n) = child_node.get("name").and_then(|v| v.as_string()) {
                                name = n.to_string();
                            }
                            let id = name.clone(); // Use name as ID for easy linking in KDL

                            let mut image = ImageDef { tag: "".to_string(), checksum: None };
                            let mut command = "".to_string();
                            let mut resources = ResourceDef { cpu: 1.0, mem: 1.0, disk: 1.0 };
                            let mut inputs = BTreeMap::new();
                            let mut static_outputs = BTreeMap::new();
                            let mut glob_outputs = Vec::new();
                            let mut retry = None;

                            if let Some(process_children) = child_node.children() {
                                for proc_child in process_children.nodes() {
                                    match proc_child.name().value() {
                                        "image" => {
                                            if let Some(tag) = proc_child.get(0).and_then(|v| v.as_string()) {
                                                image.tag = tag.to_string();
                                            }
                                        }
                                        "command" => {
                                            if let Some(cmd) = proc_child.get(0).and_then(|v| v.as_string()) {
                                                command = cmd.to_string();
                                            }
                                        }
                                        "resources" => {
                                            if let Some(cpu) = proc_child.get("cpu").and_then(|v| v.as_integer()) { resources.cpu = cpu as f64; }
                                            if let Some(cpu) = proc_child.get("cpu").and_then(|v| v.as_float()) { resources.cpu = cpu; }
                                            if let Some(mem) = proc_child.get("mem").and_then(|v| v.as_integer()) { resources.mem = mem as f64; }
                                            if let Some(mem) = proc_child.get("mem").and_then(|v| v.as_float()) { resources.mem = mem; }
                                            if let Some(disk) = proc_child.get("disk").and_then(|v| v.as_integer()) { resources.disk = disk as f64; }
                                            if let Some(disk) = proc_child.get("disk").and_then(|v| v.as_float()) { resources.disk = disk; }
                                        }
                                        "inputs" => {
                                            if let Some(in_children) = proc_child.children() {
                                                for in_node in in_children.nodes() {
                                                    let key = in_node.name().value().to_string();
                                                    if let Some(val) = in_node.get(0).and_then(|v| v.as_string()) {
                                                        inputs.insert(key, InputDef {
                                                            channel_id: val.to_string(),
                                                            format: in_node.get("format").and_then(|v| v.as_string()).unwrap_or("generic").to_string(),
                                                        });
                                                    }
                                                }
                                            }
                                        }
                                        "outputs" => {
                                            if let Some(out_children) = proc_child.children() {
                                                for out_node in out_children.nodes() {
                                                    let key = out_node.name().value().to_string();
                                                    if let Some(val) = out_node.get(0).and_then(|v| v.as_string()) {
                                                        if val.contains('*') {
                                                            glob_outputs.push(val.to_string());
                                                        } else {
                                                            static_outputs.insert(key, OutputFileDef {
                                                                uri: val.to_string(),
                                                                format: out_node.get("format").and_then(|v| v.as_string()).unwrap_or("generic").to_string(),
                                                            });
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        "retry" => {
                                            if proc_child.get(0).is_some() {
                                                return Err(ValidationError::InvalidRetryFormat {
                                                    process_id: id.clone(),
                                                });
                                            }

                                            let backoff = proc_child.get("backoff").and_then(|v| v.as_string()).unwrap_or("linear");
                                            let count = proc_child.get("count").and_then(|v| v.as_integer()).unwrap_or(3) as u32;
                                            match backoff {
                                                "exponential" => {
                                                    retry = Some(RetryDef::Exponential {
                                                        count,
                                                        exponent: proc_child.get("exponent").and_then(|v| v.as_float()).unwrap_or(2.0),
                                                        initial_delay: proc_child.get("initial_delay").and_then(|v| v.as_integer()).unwrap_or(500) as u32,
                                                    });
                                                }
                                                "linear" => {
                                                    let mut delays = Vec::new();
                                                    if let Some(d) = proc_child.get("delays").and_then(|v| v.as_string()) {
                                                        for x in d.split(',') {
                                                            if let Ok(num) = x.trim().parse::<u32>() {
                                                                delays.push(num);
                                                            }
                                                        }
                                                    }
                                                    if delays.is_empty() { delays.push(1000); }
                                                    // Pad or truncate
                                                    if delays.len() < count as usize {
                                                        let last = *delays.last().unwrap_or(&1000);
                                                        delays.resize(count as usize, last);
                                                    } else if delays.len() > count as usize {
                                                        delays.truncate(count as usize);
                                                    }
                                                    retry = Some(RetryDef::Linear { count, delays });
                                                }
                                                other => {
                                                    return Err(ValidationError::InvalidRetryStrategy {
                                                        process_id: id.clone(),
                                                        strategy: other.to_string(),
                                                    });
                                                }
                                            }
                                        }
                                        _ => {}
                                    }
                                }
                            }

                            let outputs = if !glob_outputs.is_empty() {
                                OutputDef::Glob(glob_outputs)
                            } else {
                                OutputDef::Static(static_outputs)
                            };

                            processes.push(ProcessDescriptor {
                                id,
                                name,
                                image,
                                command,
                                inputs,
                                outputs,
                                resources,
                                retry,
                            });
                        }
                        "channel" => {
                            let id = child_node.get(0).and_then(|v| v.as_string()).unwrap_or_else(|| "").to_string();
                            let t = child_node.get("type").and_then(|v| v.as_string()).unwrap_or("path");
                            let source_val = child_node.get("source").and_then(|v| v.as_string()).unwrap_or("");

                            let source = match t {
                                "literal" => ChannelSource::Literal { value: source_val.to_string() },
                                "result" => ChannelSource::Result { process_id: source_val.to_string() },
                                "zip" => ChannelSource::Zip { upstreams: source_val.split(',').map(|s| s.trim().to_string()).collect() },
                                _ => ChannelSource::FromPath { glob: source_val.to_string() },
                            };

                            let channel_type = match t {
                                "literal" => ChannelType::Literal,
                                "result" => ChannelType::Result,
                                "zip" => ChannelType::Zip,
                                _ => ChannelType::Path,
                            };

                            channels.push(ChannelDef {
                                id,
                                channel_type,
                                source,
                                format: child_node.get("format").and_then(|v| v.as_string()).unwrap_or("generic").to_string(),
                            });
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    let workflow_name = match workflow_name {
        Some(name) => name,
        None => return Err(ValidationError::NoWorkflowFound),
    };

    let mut seen: HashSet<&str> = HashSet::new();
    for proc in &processes {
        if !seen.insert(proc.name.as_str()) {
            return Err(ValidationError::DuplicateProcessName {
                workflow_name: workflow_name.clone(),
                name: proc.name.clone(),
            });
        }
    }

    let mut channel_formats = HashMap::new();
    for ch in &channels {
        channel_formats.insert(ch.id.clone(), ch.format.clone());
    }

    for proc in &processes {
        for (_input_name, input_def) in &proc.inputs {
            if let Some(ch_format) = channel_formats.get(&input_def.channel_id) {
                if input_def.format != "generic" && ch_format != "generic" && input_def.format != *ch_format {
                    return Err(ValidationError::TypeMismatch {
                        process_id: proc.id.clone(),
                        expected: input_def.format.clone(),
                        got: ch_format.clone(),
                    });
                }
            }
        }
    }

    Ok(WorkflowPlan {
        version: 1,
        name: workflow_name,
        processes,
        channels,
    })
}
