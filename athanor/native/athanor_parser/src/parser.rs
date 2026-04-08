use std::collections::{BTreeMap, HashMap};

use anyhow::anyhow;
use kdl::{KdlDocument, KdlNode};

use crate::error::{ValidationError, ValidationErrors};
use crate::ir::{
    ChannelDef, ChannelSource, ChannelType, ImageDef, InputDef, OutputDef, OutputFileDef,
    ProcessDescriptor, ResourceDef, RetryDef, WorkflowPlan,
};

const MAX_NAME_LEN: usize = 120;

fn validate_name(name: &str, context: &str) -> anyhow::Result<()> {
    if name.is_empty() {
        return Err(anyhow!("{context}: name must not be empty"));
    }
    if name.len() > MAX_NAME_LEN {
        return Err(anyhow!(
            "{context}: name '{}' exceeds {} characters",
            name, MAX_NAME_LEN
        ));
    }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.') {
        return Err(anyhow!(
            "{context}: name '{name}' contains invalid characters"
        ));
    }
    Ok(())
}

pub fn parse(source: &str) -> Result<WorkflowPlan, ValidationError> {
    let document = match source.parse::<KdlDocument>() {
        Ok(doc) => doc,
        Err(e) => return Err(ValidationError::InternalParseError { message: e.to_string() }),
    };

    let mut workflow_name = None;
    let mut processes = Vec::new();
    let mut channels = Vec::new();

    let mut templates: HashMap<String, KdlNode> = HashMap::new();

    for node in document.nodes() {
        if node.name().value() == "template" {
            if let Some(name) = node.get(0).and_then(|v| v.as_string()) {
                templates.insert(name.to_string(), node.clone());
            }
        }
    }

    let mut counter = 0;
    let mut next_id = || {
        let id = format!("id_{counter}");
        counter += 1;
        id
    };

    for node in document.nodes() {
        match node.name().value() {
            "workflow" => {
                if let Some(name) = node.get(0).and_then(|v| v.as_string()) {
                    workflow_name = Some(name.to_string());
                } else if let Some(name) = node.get("name").and_then(|v| v.as_string()) {
                    workflow_name = Some(name.to_string());
                }
            }
            "process" => {
                let id = next_id();
                let mut name = node.get(0).and_then(|v| v.as_string()).unwrap_or("").to_string();
                if let Some(n) = node.get("name").and_then(|v| v.as_string()) {
                    name = n.to_string();
                }
                
                let mut image = ImageDef { tag: "".to_string(), checksum: None };
                let mut command = "".to_string();
                let mut resources = ResourceDef { cpu: 1.0, mem: 1.0, disk: 1.0 };
                let inputs = BTreeMap::new();
                let outputs = OutputDef::Static(BTreeMap::new());

                if let Some(children) = node.children() {
                    for child in children.nodes() {
                        match child.name().value() {
                            "image" => {
                                if let Some(tag) = child.get(0).and_then(|v| v.as_string()) {
                                    image.tag = tag.to_string();
                                }
                            }
                            "command" => {
                                if let Some(cmd) = child.get(0).and_then(|v| v.as_string()) {
                                    command = cmd.to_string();
                                }
                            }
                            "resources" => {
                                if let Some(cpu) = child.get("cpu").and_then(|v| v.as_integer()) {
                                    resources.cpu = cpu as f64;
                                }
                                if let Some(cpu) = child.get("cpu").and_then(|v| v.as_float()) {
                                    resources.cpu = cpu;
                                }
                                if let Some(mem) = child.get("mem").and_then(|v| v.as_integer()) {
                                    resources.mem = mem as f64;
                                }
                                if let Some(mem) = child.get("mem").and_then(|v| v.as_float()) {
                                    resources.mem = mem;
                                }
                                if let Some(disk) = child.get("disk").and_then(|v| v.as_integer()) {
                                    resources.disk = disk as f64;
                                }
                                if let Some(disk) = child.get("disk").and_then(|v| v.as_float()) {
                                    resources.disk = disk;
                                }
                            }
                            _ => {}
                        }
                    }
                }

                processes.push(ProcessDescriptor {
                    id,
                    name,
                    image,
                    command,
                    inputs,
                    outputs,
                    resources,
                    retry: None,
                });
            }
            "channel" => {
                let id = next_id();
                channels.push(ChannelDef {
                    id,
                    channel_type: ChannelType::Path,
                    source: ChannelSource::Literal { value: "".to_string() },
                    format: "".to_string(),
                });
            }
            _ => {}
        }
    }

    let workflow_name = match workflow_name {
        Some(name) => name,
        None => return Err(ValidationError::NoWorkflowFound),
    };

    Ok(WorkflowPlan {
        version: 1,
        name: workflow_name,
        processes,
        channels,
    })
}
