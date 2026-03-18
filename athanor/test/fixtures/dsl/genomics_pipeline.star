# Genomics Pipeline — static output paths
# Three processes: align, call_variants, merge_vcfs

def align(ref, reads):
    process(
        image   = "genomics/bwa:0.7.17",
        command = "bwa mem -t {cpu} {ref} {reads} | samtools sort -o {output}",
        inputs  = {
            "ref":   ref,
            "reads": reads,
        },
        outputs = {
            "output": "s3://my-bucket/aligned/{reads.stem}.bam",
        },
        resources = {
            "cpu":  8,
            "mem":  16.0,
            "disk": 50.0,
        },
    )

def call_variants(bam, ref):
    process(
        image   = "genomics/gatk:4.4",
        command = "gatk HaplotypeCaller -R {ref} -I {bam} -O {vcf}",
        inputs  = {
            "bam": bam,
            "ref": ref,
        },
        outputs = {
            "vcf": "s3://my-bucket/variants/{bam.stem}.vcf.gz",
        },
        resources = {
            "cpu":  4,
            "mem":  32.0,
            "disk": 20.0,
        },
    )

def merge_vcfs(vcfs):
    process(
        image   = "genomics/bcftools:1.18",
        command = "bcftools merge {vcfs} -o {merged}",
        inputs  = {
            "vcfs": vcfs,
        },
        outputs = {
            "merged": "s3://my-bucket/cohort/merged.vcf.gz",
        },
        resources = {
            "cpu":  2,
            "mem":  8.0,
            "disk": 10.0,
        },
    )

def main():
    workflow(
        name = "genomics_pipeline",
        channels=[
            channel_literal("s3://my-bucket/refs/hg38.fa"),
            channel_from_path("s3://my-bucket/data/*.fastq.gz")
        ],
        processes=[
            align("s3://my-bucket/refs/hg38.fa", "s3://my-bucket/data/sample_R1.fq.gz"),
            call_variants("s3://my-bucket/aligned/sample_R1.bam", "s3://my-bucket/refs/hg38.fa"),
            merge_vcfs("s3://my-bucket/variants/sample_R1.vcf.gz")
        ]
    )
