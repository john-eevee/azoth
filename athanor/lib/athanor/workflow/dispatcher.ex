defmodule Athanor.Workflow.Dispatcher do
  @moduledoc """
  Behaviour for dispatching job vouchers to Quicksilver workers.

  The dispatcher is the single exit point from the control-plane toward the
  data-plane. Athanor never sends raw data — it sends a voucher containing
  enough metadata for the worker to fetch its own inputs, execute the task,
  and publish results back.

  For Phase 1 the `StubDispatcher` is used, which logs the voucher and returns
  immediately. The real gRPC implementation ships in Phase 5 (AZ-501/502).
  """

  alias Athanor.Workflow

  @typedoc """
  A job voucher — everything Quicksilver needs to execute a task.
  Modelled after the `%Job{}` example in architecture.md.
  """
  @type voucher() :: %{
          workflow_id: Workflow.id(),
          fingerprint: Workflow.fingerprint(),
          image: String.t(),
          command: String.t(),
          inputs: [%{name: String.t(), uri: String.t()}],
          output_search_patterns: [Path.t()],
          resources: %{
            cpu: float() | :inf,
            mem: non_neg_integer() | :inf,
            disk: non_neg_integer() | :inf
          }
        }

  @doc """
  Dispatch a task to a Quicksilver worker.

  Returns `{:ok, dispatch_ref}` on success or `{:error, reason}` on failure.
  The `dispatch_ref` is an opaque term the caller can use to correlate future
  status callbacks. For the stub implementation it is simply the fingerprint.
  """
  @callback dispatch(voucher()) :: {:ok, dispatch_ref :: term()} | {:error, reason :: term()}

  @doc """
  Build a voucher from a workflow task and its resolved process definition.
  """
  @spec build_voucher(Workflow.id(), Workflow.task(), Workflow.process()) :: voucher()
  def build_voucher(workflow_id, task, process) do
    inputs =
      Enum.map(task.input_artifacts, fn artifact ->
        # name is the artifact URI used as a stable key; workers resolve the actual path
        %{name: to_string(artifact.uri), uri: to_string(artifact.uri)}
      end)

    %{
      workflow_id: workflow_id,
      fingerprint: task.fingerprint,
      image: process.image,
      command: process.command,
      inputs: inputs,
      output_search_patterns: process.output_search_patterns,
      resources: process.resources
    }
  end
end

defmodule Athanor.Workflow.StubDispatcher do
  @moduledoc """
  Phase 1 stub implementation of `Athanor.Workflow.Dispatcher`.

  Logs the voucher contents so the execution intent is visible during
  development and testing. Always succeeds, returning the fingerprint as the
  dispatch ref. The real gRPC implementation replaces this in Phase 5.
  """

  @behaviour Athanor.Workflow.Dispatcher

  require Logger

  @impl true
  def dispatch(voucher) do
    Logger.info(
      "[StubDispatcher] voucher dispatched",
      workflow_id: voucher.workflow_id,
      fingerprint: voucher.fingerprint,
      image: voucher.image,
      command: voucher.command,
      input_count: length(voucher.inputs),
      output_patterns: voucher.output_search_patterns,
      resources: inspect(voucher.resources)
    )

    {:ok, voucher.fingerprint}
  end
end
