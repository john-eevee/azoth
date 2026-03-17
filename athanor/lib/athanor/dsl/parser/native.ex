defmodule Athanor.DSL.Parser.Native do
  @moduledoc false

  use Rustler,
    otp_app: :athanor,
    crate: "athanor_parser"

  # Stubs replaced at runtime by the Rust NIF.

  @spec parse_workflow(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_workflow(_source), do: :erlang.nif_error(:nif_not_loaded)

  @spec fingerprint_json(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def fingerprint_json(_json), do: :erlang.nif_error(:nif_not_loaded)
end
