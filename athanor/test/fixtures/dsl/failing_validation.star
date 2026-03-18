def bad_process(data):
    return process(
        image   = "test:latest",
        command = "process {input} {unknown_placeholder}",
        inputs  = {"input": data},
        outputs = {"result": "http://bad-scheme/out.txt"},
        resources = {"cpu": -1, "mem": 0.0, "disk": -5.0},
    )

def main():
    data = channel_literal("s3://bucket/input.txt")
    out = bad_process(data)
    workflow(name = "bad_workflow", target = out)
