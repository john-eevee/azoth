defmodule Athanor.Storage.Resolver do
  @moduledoc """
  Facade for resolving globs using the configured `Athanor.Storage.GlobResolver`.

  Defaults to `Athanor.Storage.LocalGlobResolver` if not configured.
  """

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
