def process_r1():
    return process(
        image = "alpine",
        command = "echo R1",
        inputs = {},
        outputs = {"out": "s3://r1.fastq"},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )

def process_r2():
    return process(
        image = "alpine",
        command = "echo R2",
        inputs = {},
        outputs = {"out": "s3://r2.fastq"},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )

def align(reads):
    return process(
        image = "bwa",
        command = "bwa mem {reads}",
        inputs = {"reads": reads},
        outputs = {"bam": "s3://aligned.bam"},
        resources = {"cpu": 1, "mem": 1, "disk": 1}
    )

def main():
    r1 = process_r1()
    r2 = process_r2()
    
    paired = channel_zip(r1, r2)
    
    bam = align(paired)
    
    workflow(name = "zip_test")