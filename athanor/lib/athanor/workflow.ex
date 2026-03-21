defmodule Athanor.Workflow do
  @moduledoc """
  The Workflow context contains types and structures for defining and executing
  reactive workflows in Athanor.

  ## Supervision Tree

  ```mermaid
  graph TD
      DS[DynamicSupervisor<br/>Athanor.Workflow.Supervisor] --> Instance[Instance<br/>Athanor.Workflow.Instance]
      Instance --> Registry[Registry<br/>Athanor.Workflow.Registry]
      Instance --> Scheduler[Scheduler<br/>Athanor.Workflow.Scheduler]
      Instance --> TaskMonitor[TaskMonitor<br/>Athanor.Workflow.TaskMonitor]
  ```

  ## Messaging Overview

  ```mermaid
  sequenceDiagram
      participant User as User/API
      participant Reg as Registry
      participant Sch as Scheduler
      participant TM as TaskMonitor
      participant Dis as Dispatcher (Stub)

      User->>Reg: register_workflow(channels, processes)
      Reg-->>User: :ok

      User->>Sch: register_process(process_id, process)
      Sch-->>User: :ok

      User->>Sch: subscribe(channel_id, process_id)
      Sch-->>User: :ok

      loop As processes publish artifacts
          User->>Sch: publish(channel_id, artifacts)
          Sch->>Reg: get_subscriptions(channel_id) (internal)
          Reg-->>Sch: [process_id, ...]
          Sch->>TM: register(fingerprint, task_pid) (when dispatching)
          TM-->>Sch: :ok
          Sch->>Dis: dispatch(voucher)
          Dis-->>Sch: {:ok, fingerprint}
          Dis->>TM: (logs voucher)
          TM->>Sch: (monitor DOWN or task completion)
          Sch->>TM: unregister(fingerprint)
          Sch->>Sch: complete_task/3 or fail_task/2
          Sch->>Sch: (update running tasks, trigger fan-out)
      end
  ```

  The workflow execution follows the reactive scheduler pattern where tasks are
  dispatched when input artifacts become available on channels, with per-process
  cursors ensuring each subscriber sees every artifact.
  """

  alias Athanor.IndexedBuffer

  @type id() :: Uniq.UUID

  @type indexed(t) :: %{non_neg_integer() => t}

  @type cursor() :: non_neg_integer()

  @type artifact() :: %{
          uri: URI.t(),
          hash: nonempty_binary(),
          metadata: map()
        }

  @type channel() :: %{
          buf: IndexedBuffer.t(),
          closed?: boolean()
        }

  @type channel_id() :: id()

  @type process_id() :: id()

  @type subscription() :: %{cursor: cursor(), process_id: process_id()}

  @type channel_subscriptions() :: {channel_id(), [subscription()]}

  @type retry_policy() ::
          %{backoff: :exponential, count: non_neg_integer(), exponent: float(), initial_delay: non_neg_integer()}
          | %{backoff: :linear, count: non_neg_integer(), delays: [non_neg_integer()]}

  @type process() :: %{
          name: String.t(),
          image: String.t(),
          command: String.t(),
          input: %{String.t() => channel_id()},
          output_search_patterns: [Path.t()],
          resources: %{
            mem: non_neg_integer() | :inf,
            cpu: float() | :inf,
            disk: non_neg_integer() | :inf
          },
          retry: retry_policy() | nil
        }

  @type task_status() :: :pending | :running | :completed | :failed

  @type fingerprint() :: nonempty_binary()

  @type task() :: %{
          process_id: process_id(),
          status: task_status(),
          fingerprint: fingerprint(),
          input_artifacts: [artifact()],
          output_artifacts: [artifact()]
        }

  defmodule Fingerprinting do
    alias Athanor.Workflow

    @type task_info() :: %{
            process_image: String.t(),
            resolved_command: String.t(),
            output_search_patterns: [Path.t()],
            input_artifacts: [Workflow.artifact()],
            output_artifacts: [Workflow.artifact()]
          }

    @spec fingerprint(task_info()) :: Workflow.fingerprint()
    def fingerprint(task_info) do
      uri_sorter = fn artifact -> artifact.uri end
      # Sort all list/map fields before hashing so the fingerprint is stable
      # regardless of insertion order. TODO: add golden tests (AZ-204).
      task_info
      |> Map.update!(:input_artifacts, &Enum.sort_by(&1, uri_sorter))
      |> Map.update!(:output_artifacts, &Enum.sort_by(&1, uri_sorter))
      |> Map.update!(:output_search_patterns, &Enum.sort/1)
      |> Enum.sort_by(&elem(&1, 0))
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
    end
  end
end
