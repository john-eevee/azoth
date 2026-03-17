defmodule Athanor.Workflow.Instance do
  @moduledoc """
  Per-workflow supervision subtree.

  Started by `Athanor.Workflow.Supervisor` (a `DynamicSupervisor`) when a
  workflow is submitted. Supervises three sibling processes that all share the
  same `workflow_id`:

    - `Athanor.Workflow.Registry`    — channel/process definitions + subscription graph
    - `Athanor.Workflow.TaskMonitor` backing Registry (Elixir Registry, must start first)
    - `Athanor.Workflow.TaskMonitor` GenServer — PID monitor + crash escalation
    - `Athanor.Workflow.Scheduler`   — reactive fan-out, concurrency gate, dispatch

  ## Usage

      {:ok, _pid} = DynamicSupervisor.start_child(
        Athanor.Workflow.Supervisor,
        {Athanor.Workflow.Instance, workflow_id: my_id}
      )
  """

  use Supervisor

  alias Athanor.Workflow
  alias Athanor.Workflow.Registry, as: WorkflowRegistry
  alias Athanor.Workflow.Scheduler
  alias Athanor.Workflow.TaskMonitor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    Supervisor.start_link(__MODULE__, opts, name: server_name(workflow_id))
  end

  @spec server_name(Workflow.id()) :: {:global, String.t()}
  def server_name(workflow_id), do: {:global, "Athanor.Workflow.Instance.#{workflow_id}"}

  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    children = [
      # Registry must start before the TaskMonitor GenServer that calls into it.
      TaskMonitor.registry_child_spec(workflow_id),
      {WorkflowRegistry, workflow_id: workflow_id},
      {TaskMonitor, workflow_id: workflow_id},
      {Scheduler, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
