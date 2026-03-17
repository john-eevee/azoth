defmodule Athanor.DSL.GoldenTest do
  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])
  @snapshots Path.join([__DIR__, "../../fixtures/dsl/snapshots"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp snapshot_path(name), do: Path.join(@snapshots, name)

  # If UPDATE_SNAPSHOTS=1 is set, write new snapshots instead of asserting.
  defp update_mode?, do: System.get_env("UPDATE_SNAPSHOTS") == "1"

  defp assert_snapshot(name, actual_json) do
    path = snapshot_path(name)

    if update_mode?() do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, actual_json <> "\n")
      :ok
    else
      expected = File.read!(path)

      assert String.trim(actual_json) == String.trim(expected),
             "Golden snapshot mismatch for #{name}.\n" <>
               "Run UPDATE_SNAPSHOTS=1 mix test to regenerate."
    end
  end

  # Produce pretty-printed JSON for readability in snapshots.
  # We re-encode from the decoded map via Jason so key order is stable
  # (Jason sorts map keys alphabetically when encoding atom-key maps).
  defp to_pretty_json(plan) do
    # Re-encode through string keys to get deterministic alphabetical order.
    plan
    |> Jason.encode!()
    |> Jason.decode!()
    |> Jason.encode!(pretty: true)
  end

  test "genomics_pipeline snapshot matches" do
    {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))
    assert_snapshot("genomics_pipeline.json", to_pretty_json(plan))
  end

  test "dynamic_split_align snapshot matches" do
    {:ok, plan} = Parser.parse(fixture("dynamic_split_align.star"))
    assert_snapshot("dynamic_split_align.json", to_pretty_json(plan))
  end
end
