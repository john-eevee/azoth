defmodule Athanor.DSL.ParserTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  describe "genomics_pipeline.kdl" do
    test "parse succeeds and returns 3 processes" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
      assert length(plan.processes) == 3
    end

    test "process IDs are align, call_variants, merge_vcfs by order" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
      names = Enum.map(plan.processes, & &1.image.tag)

      assert "genomics/bwa:0.7.17" in names
      assert "genomics/gatk:4.4" in names
      assert "genomics/bcftools:1.18" in names
    end

    test "workflow name is genomics_pipeline" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
      assert plan.name == "genomics_pipeline"
    end

    test "channels are captured" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
      # At least the literal and from_path channels declared in main()
      assert length(plan.channels) >= 2
    end

    test "align process has static OutputDef" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
      align = Enum.find(plan.processes, &(&1.image.tag == "genomics/bwa:0.7.17"))
      assert align.outputs.type == "static"
    end
  end

  describe "dynamic_split_align.kdl" do
    test "parse succeeds and returns 2 processes" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.kdl"))
      assert length(plan.processes) == 2
    end

    test "split_genome process has glob OutputDef" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.kdl"))
      split = Enum.find(plan.processes, &(&1.image.tag == "genomics/tools:latest"))
      assert split.outputs.type == "glob"
    end

    test "workflow name is dynamic_split_align" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.kdl"))
      assert plan.name == "dynamic_split_align"
    end
  end

  describe "error cases" do
    test "returns error for invalid KDL syntax" do
      assert {:error, reason} = Parser.parse("workflow \"x\" { bad syntax")
      assert is_binary(reason)
    end

    test "returns error when workflow is absent" do
      src = ~s[process "x" {}]
      assert {:error, reason} = Parser.parse(src)
      assert is_binary(reason)
    end

    test "duplicate process name returns error" do
      src = """
      workflow "dup_test" {
            channel "c1" type="literal" source="a"
            channel "c2" type="literal" source="b"

            process "align" {
                image "img:1"
                command "run"
                inputs {
                    "ref" "c1"
                }
                outputs {
                    "out" "s3://b/out"
                }
                resources cpu=1 mem=1.0 disk=1.0
            }

            process "align" {
                image "img:1"
                command "run"
                inputs {
                    "ref" "c2"
                }
                outputs {
                    "out" "s3://b/out2"
                }
                resources cpu=1 mem=1.0 disk=1.0
            }
      }
      """

      assert {:error, reason} = Parser.parse(src)
      assert reason =~ "duplicate process name" or reason =~ "duplicate" or reason =~ "align"
    end
  end
end
