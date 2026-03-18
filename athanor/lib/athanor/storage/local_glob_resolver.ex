defmodule Athanor.Storage.LocalGlobResolver do
  @moduledoc """
  A local filesystem implementation of `Athanor.Storage.GlobResolver`.

  This is primarily for local testing and execution, expanding standard
  absolute or relative path globs using Elixir's `Path.wildcard/1`.
  """
  @behaviour Athanor.Storage.GlobResolver

  @impl true
  def resolve_glob("file://" <> path) do
    resolve_local_path(path, "file://")
  end

  def resolve_glob(path) when is_binary(path) do
    if String.contains?(path, "://") do
      {:error, {:unsupported_scheme, path}}
    else
      resolve_local_path(path, "")
    end
  end

  defp resolve_local_path(path, prefix) do
    try do
      # Path.wildcard expands the glob. We map it back to include the original scheme prefix if any.
      matches =
        path
        |> Path.expand()
        |> Path.wildcard()
        |> Enum.map(&"#{prefix}#{&1}")

      {:ok, matches}
    rescue
      e -> {:error, {:resolution_failed, e}}
    end
  end
end
