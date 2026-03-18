defmodule Athanor.Workflow.InstanceTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Instance
  alias Athanor.Workflow.Registry, as: WorkflowRegistry
  alias Athanor.Workflow.Scheduler
  alias Athanor.Workflow.TaskMonitor

  test "starts a workflow instance supervision tree" do
    workflow_id = "test_instance_#{System.unique_integer([:positive])}"
    opts = [workflow_id: workflow_id]

    assert {:ok, pid} = Instance.start_link(opts)
    assert is_pid(pid)
    assert Process.alive?(pid)

    # Verify children are started
    children = Supervisor.which_children(pid)
    assert length(children) == 4

    modules = Enum.map(children, fn {_, _, _, [mod]} -> mod end) |> Enum.sort()

    # We expect Elixir.Registry, WorkflowRegistry, TaskMonitor, Scheduler
    assert Enum.member?(modules, Registry)
    assert Enum.member?(modules, WorkflowRegistry)
    assert Enum.member?(modules, TaskMonitor)
    assert Enum.member?(modules, Scheduler)

    # Check server name format
    assert Instance.server_name(workflow_id) ==
             {:global, "Athanor.Workflow.Instance.#{workflow_id}"}

    # Cleanup
    Process.exit(pid, :normal)
  end
end
