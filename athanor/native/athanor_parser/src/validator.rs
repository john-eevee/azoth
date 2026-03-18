use regex::Regex;
use std::collections::HashSet;

use crate::error::{ValidationError, ValidationErrors};
use crate::ir::{ChannelDef, OutputDef, ProcessDescriptor, WorkflowPlan};

/// Validate a complete [`WorkflowPlan`], collecting all errors before returning.
///
/// Returns `Ok(())` if all validations pass, or `Err(Vec<ValidationError>)` if any
/// validation fails. All errors are collected in a single pass.
pub fn validate_workflow(plan: &WorkflowPlan) -> Result<(), ValidationErrors> {
    let mut errors = Vec::new();

    // Validate all processes
    for process in &plan.processes {
        errors.extend(validate_process(process));
    }

    // Validate all channels
    for channel in &plan.channels {
        errors.extend(validate_channel(channel));
    }

    // Validate cross-references (channels referenced by processes must exist)
    errors.extend(validate_references(plan));

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Validate a single process descriptor.
fn validate_process(process: &ProcessDescriptor) -> ValidationErrors {
    let mut errors = Vec::new();

    // Check required fields
    if process.image.tag.is_empty() {
        errors.push(ValidationError::EmptyField {
            process_id: process.id.clone(),
            field: "image.tag",
        });
    }

    if process.command.is_empty() {
        errors.push(ValidationError::EmptyField {
            process_id: process.id.clone(),
            field: "command",
        });
    }

    if process.name.is_empty() {
        errors.push(ValidationError::EmptyField {
            process_id: process.id.clone(),
            field: "name",
        });
    }

    // Validate command placeholders
    errors.extend(validate_command_placeholders(process));

    // Validate output URIs
    errors.extend(validate_output_uris(process));

    // Validate resources
    errors.extend(validate_resources(process));

    errors
}

/// Validate that all placeholders in a command can be resolved.
fn validate_command_placeholders(process: &ProcessDescriptor) -> ValidationErrors {
    let mut errors = Vec::new();

    // Extract all {placeholder} references from the command
    let placeholders = extract_placeholders(&process.command);

    // Allowed sources: inputs, outputs (keys), and resources (cpu, mem, disk)
    let mut allowed = HashSet::new();
    allowed.extend(process.inputs.keys().cloned());

    // For static outputs, add the keys
    if let OutputDef::Static(static_outputs) = &process.outputs {
        allowed.extend(static_outputs.keys().cloned());
    }

    // Resource placeholders
    allowed.insert("cpu".to_string());
    allowed.insert("mem".to_string());
    allowed.insert("disk".to_string());

    // Check each placeholder
    for placeholder in placeholders {
        // Extract the base name (before any dot for property access like "data.stem")
        let base_name = placeholder.split('.').next().unwrap_or(&placeholder);

        if !allowed.contains(base_name) {
            errors.push(ValidationError::UnresolvablePlaceholder {
                process_id: process.id.clone(),
                placeholder,
            });
        }
    }

    errors
}

/// Extract all {placeholder} names from a string.
fn extract_placeholders(text: &str) -> Vec<String> {
    let re = Regex::new(r"\{([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\}").unwrap();
    re.captures_iter(text)
        .filter_map(|cap| cap.get(1).map(|m| m.as_str().to_string()))
        .collect()
}

/// Validate that output URIs use supported schemes.
fn validate_output_uris(process: &ProcessDescriptor) -> ValidationErrors {
    let mut errors = Vec::new();

    match &process.outputs {
        OutputDef::Static(outputs) => {
            for (key, uri) in outputs {
                if let Err(e) = validate_uri_scheme(uri, &process.id, key) {
                    errors.push(e);
                }
            }
        }
        OutputDef::Glob(_) => {
            // Glob patterns don't need URI scheme validation
        }
    }

    errors
}

/// Validate a single URI has a supported scheme.
fn validate_uri_scheme(uri: &str, process_id: &str, key: &str) -> Result<(), ValidationError> {
    // Extract scheme (everything before "://")
    if let Some(scheme_end) = uri.find("://") {
        let scheme = &uri[..scheme_end];
        // Allowed schemes: s3, gs, nfs, and relative paths (no scheme)
        if !["s3", "gs", "nfs"].contains(&scheme) {
            return Err(ValidationError::InvalidOutputScheme {
                process_id: process_id.to_string(),
                key: key.to_string(),
                scheme: scheme.to_string(),
            });
        }
        Ok(())
    } else if uri.starts_with('/') {
        // Absolute path is also okay
        Ok(())
    } else if uri.starts_with('.') {
        // Relative path is okay
        Ok(())
    } else {
        // No scheme and not a path — invalid
        Err(ValidationError::InvalidOutputScheme {
            process_id: process_id.to_string(),
            key: key.to_string(),
            scheme: "none".to_string(),
        })
    }
}

/// Validate resource values are positive numbers.
fn validate_resources(process: &ProcessDescriptor) -> ValidationErrors {
    let mut errors = Vec::new();

    if process.resources.cpu <= 0.0 {
        errors.push(ValidationError::NonPositiveResource {
            process_id: process.id.clone(),
            resource: "cpu",
            value: process.resources.cpu,
        });
    }

    if process.resources.mem <= 0.0 {
        errors.push(ValidationError::NonPositiveResource {
            process_id: process.id.clone(),
            resource: "mem",
            value: process.resources.mem,
        });
    }

    if process.resources.disk <= 0.0 {
        errors.push(ValidationError::NonPositiveResource {
            process_id: process.id.clone(),
            resource: "disk",
            value: process.resources.disk,
        });
    }

    errors
}

/// Validate that channels referenced by processes exist.
fn validate_references(plan: &WorkflowPlan) -> ValidationErrors {
    let _valid_channels: HashSet<String> = plan.channels.iter().map(|c| c.id.clone()).collect();

    // All references to channels in this plan should exist
    // (For now, we just collect process/channel IDs; future: validate wiring)

    Vec::new()
}

/// Validate a single channel definition.
fn validate_channel(channel: &ChannelDef) -> ValidationErrors {
    let mut errors = Vec::new();

    if channel.id.is_empty() {
        errors.push(ValidationError::EmptyField {
            process_id: "unknown".to_string(),
            field: "channel.id",
        });
    }

    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ir::ResourceDef;

    fn make_test_process(id: &str, name: &str) -> ProcessDescriptor {
        ProcessDescriptor {
            id: id.to_string(),
            name: name.to_string(),
            image: "test:latest".to_string(),
            command: "echo test".to_string(),
            inputs: Default::default(),
            outputs: OutputDef::Static(Default::default()),
            resources: ResourceDef {
                cpu: 1.0,
                mem: 2.0,
                disk: 10.0,
            },
        }
    }

    #[test]
    fn test_validate_process_missing_image() {
        let mut proc = make_test_process("id_0", "test");
        proc.image.clear();

        let errs = validate_process(&proc);
        assert_eq!(errs.len(), 1);
        match &errs[0] {
            ValidationError::EmptyField { field, .. } => assert_eq!(*field, "image"),
            _ => panic!("Expected EmptyField error"),
        }
    }

    #[test]
    fn test_validate_command_placeholder_resolution() {
        let mut proc = make_test_process("id_0", "test");
        proc.command = "process {input1} {unknown}".to_string();
        proc.inputs
            .insert("input1".to_string(), "s3://bucket/file".to_string());

        let errs = validate_process(&proc);
        assert_eq!(errs.len(), 1);
        match &errs[0] {
            ValidationError::UnresolvablePlaceholder { placeholder, .. } => {
                assert_eq!(placeholder, "unknown")
            }
            _ => panic!("Expected UnresolvablePlaceholder error"),
        }
    }

    #[test]
    fn test_validate_placeholder_cpu_mem_disk() {
        let mut proc = make_test_process("id_0", "test");
        proc.command = "process -c {cpu} -m {mem} -d {disk}".to_string();

        let errs = validate_command_placeholders(&proc);
        assert!(errs.is_empty(), "Resource placeholders should be valid");
    }

    #[test]
    fn test_validate_output_uri_s3() {
        let mut proc = make_test_process("id_0", "test");
        let mut outputs = std::collections::BTreeMap::new();
        outputs.insert(
            "result".to_string(),
            "s3://bucket/path/file.txt".to_string(),
        );
        proc.outputs = OutputDef::Static(outputs);

        let errs = validate_output_uris(&proc);
        assert!(errs.is_empty(), "Valid s3 URI should pass");
    }

    #[test]
    fn test_validate_output_uri_invalid_scheme() {
        let mut proc = make_test_process("id_0", "test");
        let mut outputs = std::collections::BTreeMap::new();
        outputs.insert("result".to_string(), "http://bucket/file.txt".to_string());
        proc.outputs = OutputDef::Static(outputs);

        let errs = validate_output_uris(&proc);
        assert_eq!(errs.len(), 1);
        match &errs[0] {
            ValidationError::InvalidOutputScheme { scheme, .. } => assert_eq!(scheme, "http"),
            _ => panic!("Expected InvalidOutputScheme error"),
        }
    }

    #[test]
    fn test_validate_resources_negative() {
        let mut proc = make_test_process("id_0", "test");
        proc.resources.cpu = -1.0;

        let errs = validate_resources(&proc);
        assert_eq!(errs.len(), 1);
        match &errs[0] {
            ValidationError::NonPositiveResource { resource, .. } => assert_eq!(*resource, "cpu"),
            _ => panic!("Expected NonPositiveResource error"),
        }
    }

    #[test]
    fn test_extract_placeholders() {
        let text = "command {input1} {ref.stem} more {output} stuff";
        let placeholders = extract_placeholders(text);
        assert_eq!(placeholders.len(), 3);
        assert!(placeholders.contains(&"input1".to_string()));
        assert!(placeholders.contains(&"ref.stem".to_string()));
        assert!(placeholders.contains(&"output".to_string()));
    }
}
