use crate::error::ValidationError;
use crate::ir::{ImageDef, OutputDef, OutputFileDef, ProcessDescriptor, ResourceDef};
use crate::validator::validate_process;
use std::collections::BTreeMap;

pub fn make_test_process(id: &str, name: &str) -> ProcessDescriptor {
    ProcessDescriptor {
        id: id.to_string(),
        name: name.to_string(),
        image: ImageDef {
            tag: "test:latest".to_string(),
            checksum: None,
        },
        command: "echo test".to_string(),
        inputs: Default::default(),
        outputs: OutputDef::Static(Default::default()),
        resources: ResourceDef {
            cpu: 1.0,
            mem: 2.0,
            disk: 10.0,
        },
        retry: None,
    }
}

#[test]
fn test_validate_process_missing_image_tag() {
    let mut proc = make_test_process("id_0", "test");
    proc.image.tag.clear();

    let errs = validate_process(&proc);
    assert_eq!(errs.len(), 1);
    match &errs[0] {
        ValidationError::EmptyField { field, .. } => assert_eq!(*field, "image.tag"),
        _ => panic!("Expected EmptyField error"),
    }
}

#[test]
fn test_validate_process_missing_command() {
    let mut proc = make_test_process("id_0", "test");
    proc.command.clear();

    let errs = validate_process(&proc);
    assert!(errs.iter().any(|e| matches!(
        e,
        ValidationError::EmptyField {
            field: "command",
            ..
        }
    )));
}

#[test]
fn test_validate_process_missing_name() {
    let mut proc = make_test_process("id_0", "test");
    proc.name.clear();

    let errs = validate_process(&proc);
    assert!(errs
        .iter()
        .any(|e| matches!(e, ValidationError::EmptyField { field: "name", .. })));
}

#[test]
fn test_validate_output_uri_schemes() {
    let mut proc = make_test_process("id_0", "test");
    let mut outputs = BTreeMap::new();
    outputs.insert(
        "valid_s3".to_string(),
        OutputFileDef {
            uri: "s3://bucket/key".to_string(),
            format: "generic".to_string(),
        },
    );
    outputs.insert(
        "valid_gs".to_string(),
        OutputFileDef {
            uri: "gs://bucket/key".to_string(),
            format: "generic".to_string(),
        },
    );
    outputs.insert(
        "valid_nfs".to_string(),
        OutputFileDef {
            uri: "nfs://path/to/file".to_string(),
            format: "generic".to_string(),
        },
    );
    outputs.insert(
        "invalid_http".to_string(),
        OutputFileDef {
            uri: "http://example.com".to_string(),
            format: "generic".to_string(),
        },
    );
    proc.outputs = OutputDef::Static(outputs);

    let errs = validate_process(&proc);
    assert_eq!(errs.len(), 1);
    match &errs[0] {
        ValidationError::InvalidOutputScheme { scheme, .. } => assert_eq!(scheme, "http"),
        _ => panic!("Expected InvalidOutputScheme error"),
    }
}

#[test]
fn test_validate_resources_non_positive() {
    let mut proc = make_test_process("id_0", "test");
    proc.resources.cpu = 0.0;
    proc.resources.mem = -1.0;

    let errs = validate_process(&proc);
    assert_eq!(errs.len(), 2);
}
