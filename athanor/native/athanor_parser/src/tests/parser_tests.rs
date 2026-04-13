use crate::error::ValidationError;
use crate::parser::parse;

#[test]
fn test_parse_valid_workflow() {
    let source = r#"
process "align" {
    image "biocontainers/bwa:v0.7.17_cv1"
    command "bwa mem -t {cpu} ref.fa {reads}"
    resources cpu=4 mem=8192 disk=100
}

workflow "test-workflow" {
}
"#;
    let plan = parse(source).expect("Should parse valid workflow");
    assert_eq!(plan.name, "test-workflow");
    assert_eq!(plan.processes.len(), 1);
    assert_eq!(plan.processes[0].name, "align");
}

#[test]
fn test_parse_missing_workflow_call() {
    let source = r#"
process "only-process" {
    image "test"
    command "test"
}
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::NoWorkflowFound)));
}

#[test]
fn test_parse_kdl_syntax_error() {
    let source = r#"
workflow {
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::InternalParseError { .. })));
}
