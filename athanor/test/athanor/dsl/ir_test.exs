defmodule Athanor.DSL.IRTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  describe "JSON roundtrip" do
    test "genomics_pipeline serialises and deserialises losslessly" do
      src = fixture("genomics_pipeline.star")
      {:ok, plan_a} = Parser.parse(src)
      # Re-encode to JSON and decode again — must be identical.
      json = Jason.encode!(plan_a)
      {:ok, plan_b} = Jason.decode(json, keys: :atoms)
      assert plan_a == plan_b
    end

    test "dynamic_split_align serialises and deserialises losslessly" do
      src = fixture("dynamic_split_align.star")
      {:ok, plan_a} = Parser.parse(src)
      json = Jason.encode!(plan_a)
      {:ok, plan_b} = Jason.decode(json, keys: :atoms)
      assert plan_a == plan_b
    end
  end

  describe "IR shape" do
    test "WorkflowPlan has required top-level keys" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))
      assert Map.has_key?(plan, :version)
      assert Map.has_key?(plan, :name)
      assert Map.has_key?(plan, :processes)
      assert Map.has_key?(plan, :channels)
    end

    test "ProcessDescriptor has required keys" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))
      [proc | _] = plan.processes
      assert Map.has_key?(proc, :id)
      assert Map.has_key?(proc, :image)
      assert Map.has_key?(proc, :command)
      assert Map.has_key?(proc, :inputs)
      assert Map.has_key?(proc, :outputs)
      assert Map.has_key?(proc, :resources)
    end

    test "ResourceDef has cpu, mem, disk as numbers" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))
      align = Enum.find(plan.processes, &(&1.image == "genomics/bwa:0.7.17"))
      assert align.resources.cpu == 8.0
      assert align.resources.mem == 16.0
      assert align.resources.disk == 50.0
    end

    test "static OutputDef carries named URI map" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))
      align = Enum.find(plan.processes, &(&1.image == "genomics/bwa:0.7.17"))
      # Jason decodes with keys: :atoms, so map keys are atoms.
      assert align.outputs.value[:output] =~ "s3://my-bucket/aligned/"
    end

    test "glob OutputDef carries list of patterns" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.star"))
      split = Enum.find(plan.processes, &(&1.image == "genomics/tools:latest"))
      assert is_list(split.outputs.value)
      assert hd(split.outputs.value) == "./chunks/*.fa"
    end
  end
end
