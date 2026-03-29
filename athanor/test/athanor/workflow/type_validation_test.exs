defmodule Athanor.Workflow.TypeValidationTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  test "workflow validation fails when input types do not match channel types" do
    source = """
    def main():
        fastq_ch = channel_from_path("*.fq", format="fastq")
        
        process(
            name="haplotype_caller",
            command="echo {bam}",
            inputs={"bam": Input(fastq_ch, format="bam")},
            outputs={"vcf": Output("./out.vcf", format="vcf")},
            resources={"cpu": 1, "mem": 1, "disk": 1},
            image="test"
        )
        
        workflow(name="test")
    """

    assert {:error, msg} = Parser.parse(source)
    assert String.contains?(msg, "type mismatch on input channel")
    assert String.contains?(msg, "expected format 'bam', but channel provides 'fastq'")
  end

  test "workflow validation passes when types match or are generic" do
    source = """
    def main():
        fastq_ch = channel_from_path("*.fq", format="fastq")
        
        aligned = process(
            name="align",
            command="echo {reads}",
            inputs={"reads": Input(fastq_ch, format="fastq")},
            outputs={"bam": Output("./out.bam", format="bam")},
            resources={"cpu": 1, "mem": 1, "disk": 1},
            image="test"
        )
        
        process(
            name="haplotype_caller",
            command="echo {bam}",
            inputs={"bam": Input(aligned, format="bam")},
            outputs={"vcf": Output("./out.vcf", format="vcf")},
            resources={"cpu": 1, "mem": 1, "disk": 1},
            image="test"
        )
        
        workflow(name="test")
    """

    assert {:ok, _plan} = Parser.parse(source)
  end
end
