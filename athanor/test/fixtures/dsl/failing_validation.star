def bad_process(data):
    process(
        image   = "test:latest",
        command = "process {input} {unknown_placeholder}",
        inputs  = {"input": data},
        outputs = {"result": "http://bad-scheme/out.txt"},
        resources = {"cpu": -1, "mem": 0.0, "disk": -5.0},
    )

def main():
    bad_process("s3://bucket/input.txt")
    workflow(name = "bad_workflow")
