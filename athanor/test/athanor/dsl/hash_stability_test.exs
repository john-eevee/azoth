defmodule Athanor.DSL.HashStabilityTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])
  @iterations 100

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  test "genomics_pipeline fingerprint is stable across #{@iterations} parses" do
    src = fixture("genomics_pipeline.star")

    hashes =
      for _ <- 1..@iterations do
        {:ok, h} = Parser.fingerprint(src)
        h
      end

    assert Enum.uniq(hashes) |> length() == 1,
           "Expected identical fingerprints, got: #{inspect(Enum.uniq(hashes))}"
  end

  test "dynamic_split_align fingerprint is stable across #{@iterations} parses" do
    src = fixture("dynamic_split_align.star")

    hashes =
      for _ <- 1..@iterations do
        {:ok, h} = Parser.fingerprint(src)
        h
      end

    assert Enum.uniq(hashes) |> length() == 1,
           "Expected identical fingerprints, got: #{inspect(Enum.uniq(hashes))}"
  end

  test "changing a command string changes the fingerprint" do
    src_a = fixture("genomics_pipeline.star")

    src_b =
      String.replace(
        src_a,
        "bwa mem -t {cpu} {ref} {reads} | samtools sort -o {output}",
        "bwa mem -t {cpu} {ref} {reads} | samtools sort -@ 4 -o {output}"
      )

    {:ok, hash_a} = Parser.fingerprint(src_a)
    {:ok, hash_b} = Parser.fingerprint(src_b)

    refute hash_a == hash_b, "Different commands must produce different fingerprints"
  end
end
