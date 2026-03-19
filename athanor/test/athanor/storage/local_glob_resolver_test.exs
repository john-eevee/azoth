defmodule Athanor.Storage.LocalGlobResolverTest do
  use ExUnit.Case, async: true

  alias Athanor.Storage.GlobResolver
  alias Athanor.Storage.LocalGlobResolver

  setup do
    # Create some dummy files in a temp directory for globbing
    temp_dir = System.tmp_dir!() |> Path.join("athanor_glob_test_#{System.unique_integer()}")
    File.mkdir_p!(temp_dir)

    File.write!(Path.join(temp_dir, "1.txt"), "hello")
    File.write!(Path.join(temp_dir, "2.txt"), "world")
    File.write!(Path.join(temp_dir, "3.csv"), "data")

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    Application.put_env(:athanor, :glob_resolver, LocalGlobResolver)

    %{temp_dir: temp_dir}
  end

  test "resolves local paths correctly", %{temp_dir: temp_dir} do
    pattern = Path.join(temp_dir, "*.txt")
    {:ok, files} = LocalGlobResolver.resolve_glob(pattern)

    assert length(files) == 2
    assert Enum.any?(files, &String.ends_with?(&1, "1.txt"))
    assert Enum.any?(files, &String.ends_with?(&1, "2.txt"))
    refute Enum.any?(files, &String.ends_with?(&1, "3.csv"))
  end

  test "resolves file:// scheme correctly", %{temp_dir: temp_dir} do
    pattern = "file://" <> Path.join(temp_dir, "*.txt")
    {:ok, files} = GlobResolver.resolve_glob(pattern)

    assert length(files) == 2
    assert Enum.any?(files, &String.starts_with?(&1, "file://"))
    assert Enum.any?(files, &String.ends_with?(&1, "1.txt"))
  end

  test "returns error for unsupported schemes" do
    assert {:error, {:unsupported_scheme, "s3://bucket/*.txt"}} =
             GlobResolver.resolve_glob("s3://bucket/*.txt")
  end

  test "returns empty list when no files match", %{temp_dir: temp_dir} do
    pattern = Path.join(temp_dir, "*.md")
    assert {:ok, []} = GlobResolver.resolve_glob(pattern)
  end
end
