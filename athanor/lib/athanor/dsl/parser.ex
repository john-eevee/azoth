defmodule Athanor.DSL.Parser do
  @moduledoc """
  Parses a Starlark DSL source file into a `WorkflowPlan` IR map and
  computes a deterministic SHA-256 fingerprint.

  Delegates to the Rust NIF (`athanor_parser`) via `Athanor.DSL.Parser.Native`.
  The NIF is compiled by Rustler during `mix compile`.
  """

  alias Athanor.DSL.Parser.Native

  @doc """
  Parse `source` (Starlark DSL text) and return the decoded `WorkflowPlan`
  map on success, or an `{:error, reason}` tuple on failure.

  The returned map has atom keys and matches the `WorkflowPlan` IR shape
  defined in `ir.rs`.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with {:ok, json} <- Native.parse_workflow(source),
         {:ok, plan} <- Jason.decode(json, keys: :atoms) do
      {:ok, plan}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, "JSON decode failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Parse `source` and compute the SHA-256 fingerprint of the canonical IR.

  Returns `{:ok, hex_string}` or `{:error, reason}`.
  """
  @spec fingerprint(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def fingerprint(source) when is_binary(source) do
    with {:ok, json} <- Native.parse_workflow(source) do
      Native.fingerprint_json(json)
    end
  end

  @doc """
  Parse `source` (Starlark DSL text) and return both the decoded `WorkflowPlan`
  map and its SHA-256 fingerprint on success, or an `{:error, reason}` tuple on failure.
  """
  @spec parse_and_fingerprint(String.t()) ::
          {:ok, %{plan: map(), fingerprint: String.t()}} | {:error, String.t()}
  def parse_and_fingerprint(source) when is_binary(source) do
    with {:ok, json} <- Native.parse_workflow(source),
         {:ok, plan} <- Jason.decode(json, keys: :atoms),
         {:ok, hash} <- Native.fingerprint_json(json) do
      {:ok, %{plan: plan, fingerprint: hash}}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, "JSON decode failed: #{Exception.message(e)}"}
    end
  end
end
