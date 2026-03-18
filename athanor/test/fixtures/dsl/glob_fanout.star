def producer(data):
    process(
        image = "producer:v1",
        command = "produce {input}",
        inputs = {"input": data},
        outputs = ["s3://bucket/out/*.txt"],
        resources = {"cpu": 1, "mem": 1.0, "disk": 1.0}
    )

def consumer(data):
    process(
        image = "consumer:v1",
        command = "consume {input}",
        inputs = {"input": data},
        outputs = {"out": "s3://bucket/final/{input.stem}.out"},
        resources = {"cpu": 1, "mem": 1.0, "disk": 1.0}
    )

def main():
    workflow(
        name = "glob_fanout",
        channels=[
            channel_literal("s3://bucket/start.txt"),
            channel_from_path("s3://bucket/out/*.txt")    
        ],
        processes=[
            producer("s3://bucket/start.txt"),
            consumer("s3://bucket/out/*.txt")
        ]
    )
