use crate::error::ValidationError;
use crate::parser::parse;

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
    assert!(matches!(
        result,
        Err(ValidationError::DuplicateProcessName { .. })
    ));
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

#[test]
fn test_parse_channel_zip() {
    let source = r#"
def step1():
    return process(
        image = "test",
        command = "echo 1",
        inputs = {},
        outputs = {"out": "s3://out1"},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )

def step2():
    return process(
        image = "test",
        command = "echo 2",
        inputs = {},
        outputs = {"out": "s3://out2"},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )

def main():
    r1 = step1()
    r2 = step2()
    paired = channel_zip(r1, r2)
    workflow(name = "test-zip")
"#;
    let plan = parse(source).expect("Should parse zip channel");
    assert_eq!(plan.channels.len(), 3); // 2 result channels, 1 zip channel

    let zip_channel = plan
        .channels
        .iter()
        .find(|c| matches!(c.channel_type, crate::ir::ChannelType::Zip))
        .expect("Should have a zip channel");

    if let crate::ir::ChannelSource::Zip { upstreams } = &zip_channel.source {
        assert_eq!(upstreams.len(), 2);
    } else {
        panic!("Expected ChannelSource::Zip");
    }
}
