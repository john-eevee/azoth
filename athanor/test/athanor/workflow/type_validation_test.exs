defmodule Athanor.Workflow.TypeValidationTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  test "workflow validation fails when input types do not match channel types" do
    # TODO: KDL parser currently hardcodes format="generic" and bypasses this validation.
    # We leave this test but assert it parses for now, until KDL parsing extracts `format`.
    source = """
    workflow "test" {
        channel "fastq_ch" type="path" source="*.fq" format="fastq"

        process "haplotype_caller" {
            image "test"
            command "echo {bam}"
            inputs {
                "bam" "fastq_ch" format="bam"
            }
            outputs {
                "vcf" "./out.vcf" format="vcf"
            }
            resources cpu=1 mem=1.0 disk=1.0
        }
    }
    """

    assert {:error, msg} = Parser.parse(source)
    assert is_binary(msg)
  end

  test "workflow validation passes when types match or are generic" do
    source = """
    workflow "test" {
        channel "fastq_ch" type="path" source="*.fq" format="fastq"
        channel "aligned_ch" type="result" source="align"

        process "align" {
            image "test"
            command "echo {reads}"
            inputs {
                "reads" "fastq_ch" format="fastq"
            }
            outputs {
                "bam" "./out.bam" format="bam"
            }
            resources cpu=1 mem=1.0 disk=1.0
        }

        process "haplotype_caller" {
            image "test"
            command "echo {bam}"
            inputs {
                "bam" "aligned_ch" format="bam"
            }
            outputs {
                "vcf" "./out.vcf" format="vcf"
            }
            resources cpu=1 mem=1.0 disk=1.0
        }
    }
    """

    assert {:ok, _plan} = Parser.parse(source)
  end
end
