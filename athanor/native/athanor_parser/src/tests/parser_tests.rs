use crate::parser::parse;
use crate::error::ValidationError;

#[test]
fn test_parse_valid_workflow() {
    let source = r#"
def align(reads):
    return process(
        image = "biocontainers/bwa:v0.7.17_cv1",
        command = "bwa mem -t {cpu} ref.fa {reads}",
        inputs = {"reads": reads},
        outputs = {"bam": "aligned.bam"},
        resources = {"cpu": 4, "mem": 8192, "disk": 100}
    )

def main():
    reads = channel_from_path("*.fastq.gz")
    bam = align(reads)
    workflow(name = "test-workflow")
"#;
    let plan = parse(source).expect("Should parse valid workflow");
    assert_eq!(plan.name, "test-workflow");
    assert_eq!(plan.processes.len(), 1);
    assert_eq!(plan.processes[0].name, "align");
}

#[test]
fn test_parse_missing_main() {
    let source = r#"
def not_main():
    pass
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::NoWorkflowFound)));
}

#[test]
fn test_parse_missing_workflow_call() {
    let source = r#"
def main():
    pass
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::NoWorkflowFound)));
}

#[test]
fn test_parse_duplicate_process_name() {
    let source = r#"
def main():
    process(
        name = "duplicate",
        image = "test",
        command = "echo 1",
        inputs = {},
        outputs = {},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )
    process(
        name = "duplicate",
        image = "test",
        command = "echo 2",
        inputs = {},
        outputs = {},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )
    workflow(name = "dup-test")
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::DuplicateProcessName { .. })));
}

#[test]
fn test_parse_starlark_syntax_error() {
    let source = r#"
def main(:
    pass
"#;
    let result = parse(source);
    assert!(matches!(result, Err(ValidationError::StarlarkError { .. })));
}
