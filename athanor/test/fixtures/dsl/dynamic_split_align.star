# Dynamic Split-Align — glob outputs and runtime-discovered parallelism

def split_genome(ref):
    process(
        image   = "genomics/tools:latest",
        command = "split_tool {ref} --output-dir ./chunks/",
        inputs  = {"ref": ref},
        outputs = ["./chunks/*.fa"],
        resources = {"cpu": 2, "mem": 4.0, "disk": 20.0},
    )

def align_chunk(chunk, reads):
    process(
        image   = "genomics/bwa:0.7.17",
        command = "bwa mem -t {cpu} {chunk} {reads} -o {output}",
        inputs  = {"chunk": chunk, "reads": reads},
        outputs = {"output": "s3://my-bucket/aligned/{chunk.stem}.bam"},
        resources = {"cpu": 8, "mem": 16.0, "disk": 50.0},
    )

def main():
    workflow(
        name = "dynamic_split_align",
        channels=[
            channel_literal("s3://my-bucket/refs/hg38.fa"),
            channel_literal("s3://my-bucket/data/sample_R1.fq.gz")
        ],
        processes=[
            split_genome("s3://my-bucket/refs/hg38.fa"),
            align_chunk("s3://my-bucket/refs/chr1.fa", "s3://my-bucket/data/sample_R1.fq.gz")
        ]
    )
