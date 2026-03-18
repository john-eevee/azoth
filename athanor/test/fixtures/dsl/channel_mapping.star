def process_one(in_val):
    process(
        image = "test:v1",
        command = "echo {in_val} > {out_val}",
        inputs = {"in_val": in_val},
        outputs = {"out_val": "s3://bucket/test.txt"},
        resources = {"cpu": 1, "mem": 1.0, "disk": 1.0}
    )

def process_two(in2_val):
    process(
        image = "test:v1",
        command = "cat {in2_val}",
        inputs = {"in2_val": in2_val},
        outputs = {"out2_val": "s3://bucket/out2.txt"},
        resources = {"cpu": 1, "mem": 1.0, "disk": 1.0}
    )

def main():
    workflow(
        name = "channel_mapping",
        channels=[
            channel_literal("s3://bucket/input.txt")
        ],
        processes=[
            process_one("s3://bucket/input.txt"),
            process_two("s3://bucket/test.txt")
        ]
    )
