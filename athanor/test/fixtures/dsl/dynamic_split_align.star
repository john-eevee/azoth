# Dynamic Split-Align — programmatic data flow design

def split_genome(ref):
    return process(
        image   = "genomics/tools:latest",
        command = "split_tool {ref} --output-dir ./chunks/",
        inputs  = {"ref": ref},
        outputs = ["./chunks/*.fa"],
        resources = {"cpu": 2, "mem": 4.0, "disk": 20.0},
    )

def align_chunk(chunk, reads):
    return process(
        image   = "genomics/bwa:0.7.17",
        command = "bwa mem -t {cpu} {chunk} {reads} -o {output}",
        inputs  = {"chunk": chunk, "reads": reads},
        outputs = {"output": "s3://my-bucket/aligned/{chunk.stem}.bam"},
        resources = {"cpu": 8, "mem": 16.0, "disk": 50.0},
    )

def main():
    ref = channel_literal("s3://my-bucket/refs/hg38.fa")
    reads = channel_literal("s3://my-bucket/data/sample_R1.fq.gz")

    chunks = split_genome(ref)
    bams = align_chunk(chunks, reads)

    workflow(name = "dynamic_split_align", target = bams)
