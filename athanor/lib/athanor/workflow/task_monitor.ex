defmodule Athanor.Workflow.TaskMonitor do
  @moduledoc """
  Tracks in-flight tasks for a single workflow instance.

  Each running task is registered in an Elixir `Registry` under its fingerprint
  so lookups are O(1). The monitor also watches every registered PID with
  `Process.monitor/1`; if a task process dies unexpectedly (i.e. without sending
  a clean `:task_complete` or `:task_failed` message) the monitor automatically
  calls `Scheduler.fail_task/2` so the scheduler can requeue or surface the error.

  ## Naming

  The backing Registry and this GenServer are started as part of a
  `Athanor.Workflow.Instance` supervision tree. Both are registered under
  names derived from the `workflow_id` so multiple workflows can coexist:

      registry_name  = Athanor.Workflow.TaskMonitor.registry_name(workflow_id)
      monitor_name   = Athanor.Workflow.TaskMonitor.server_name(workflow_id)
  """

  use GenServer

  alias Athanor.Workflow
  alias Athanor.Workflow.Scheduler

  # ---------------------------------------------------------------------------
  # Naming helpers
  # ---------------------------------------------------------------------------

  @spec registry_name(Workflow.id()) :: atom()
  def registry_name(workflow_id),
    do: :"Athanor.Workflow.TaskMonitor.Registry.#{workflow_id}"

  @spec server_name(Workflow.id()) :: {:global, String.t()}
  def server_name(workflow_id),
    do: {:global, "Athanor.Workflow.TaskMonitor.#{workflow_id}"}

  # ---------------------------------------------------------------------------
  # Child spec helpers — used by Instance supervisor
  # ---------------------------------------------------------------------------

  @doc "Returns the child spec for the backing Registry (must start before the GenServer)."
  @spec registry_child_spec(Workflow.id()) :: Supervisor.child_spec()
  def registry_child_spec(workflow_id) do
    %{
      id: {__MODULE__, :registry, workflow_id},
      start: {Registry, :start_link, [[keys: :unique, name: registry_name(workflow_id)]]}
    }
  end

  @doc "Returns the child spec for the monitor GenServer."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    %{
      id: {__MODULE__, workflow_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    GenServer.start_link(__MODULE__, opts, name: server_name(workflow_id))
  end

  @doc """
  Register a running task. `scheduler` is the pid/name of the workflow's
  Scheduler so the monitor can call back on unexpected crashes.
  """
  @spec register(Workflow.id(), Workflow.fingerprint(), pid(), Scheduler.t()) :: :ok
  def register(workflow_id, fingerprint, task_pid, scheduler) do
    GenServer.cast(server_name(workflow_id), {:register, fingerprint, task_pid, scheduler})
  end

  @doc "Remove a task from the monitor (called after clean completion or failure)."
  @spec unregister(Workflow.id(), Workflow.fingerprint()) :: :ok
  def unregister(workflow_id, fingerprint) do
    GenServer.cast(server_name(workflow_id), {:unregister, fingerprint})
  end

  @doc "Look up the PID registered for a fingerprint. Returns `nil` if not found."
  @spec lookup(Workflow.id(), Workflow.fingerprint()) :: pid() | nil
  def lookup(workflow_id, fingerprint) do
    case Registry.lookup(registry_name(workflow_id), fingerprint) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @typep monitor_entry :: %{
           fingerprint: Workflow.fingerprint(),
           pid: pid(),
           ref: reference(),
           scheduler: Scheduler.t()
         }

  @typep server_state :: %{
           workflow_id: Workflow.id(),
           # monitor ref → entry, for fast DOWN lookup
           monitors: %{reference() => monitor_entry()}
         }

  @impl true
  @spec init(keyword()) :: {:ok, server_state()}
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    {:ok, %{workflow_id: workflow_id, monitors: %{}}}
  end

  @impl true
  def handle_cast({:register, fingerprint, task_pid, scheduler}, state) do
    ref = Process.monitor(task_pid)

    Registry.register(registry_name(state.workflow_id), fingerprint, nil)

    entry = %{fingerprint: fingerprint, pid: task_pid, ref: ref, scheduler: scheduler}
    {:noreply, %{state | monitors: Map.put(state.monitors, ref, entry)}}
  end

  def handle_cast({:unregister, fingerprint}, state) do
    # Find the monitor entry by fingerprint and demonitor
    {ref, monitors} =
      Enum.reduce(state.monitors, {nil, state.monitors}, fn {r, e}, {found_ref, acc} ->
        if e.fingerprint == fingerprint do
          Process.demonitor(r, [:flush])
          {r, Map.delete(acc, r)}
        else
          {found_ref, acc}
        end
      end)

    if ref != nil do
      Registry.unregister(registry_name(state.workflow_id), fingerprint)
    end

    {:noreply, %{state | monitors: monitors}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {entry, monitors} ->
        Registry.unregister(registry_name(state.workflow_id), entry.fingerprint)

        # Only escalate to scheduler if the crash was unexpected (not a clean exit)
        if reason != :normal do
          Scheduler.fail_task(entry.scheduler, entry.fingerprint)
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end
end
