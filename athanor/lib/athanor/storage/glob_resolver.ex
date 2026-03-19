defmodule Athanor.Storage.GlobResolver do
  @moduledoc """
  Behaviour for resolving root-level glob URIs into concrete artifact URIs.

  This is used by the control plane to expand input `channel.from_path(...)`
  patterns before workflow execution begins, seeding the initial channels.

  Process output globs are handled differently (by the execution data plane)
  and do not use this resolver.
  """

  @doc """
  Expands a glob URI into a list of concrete URIs.

  ## Examples

      iex> Athanor.Storage.GlobResolver.resolve_glob("s3://bucket/data/*.txt")
      {:ok, ["s3://bucket/data/1.txt", "s3://bucket/data/2.txt"]}

  """
  @callback resolve_glob(uri_pattern :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Expands a glob URI using the configured backend.
  """
  def resolve_glob(uri_pattern) do
    impl().resolve_glob(uri_pattern)
  end

  defp impl do
    Application.get_env(:athanor, :glob_resolver, Athanor.Storage.LocalGlobResolver)
  end
end
