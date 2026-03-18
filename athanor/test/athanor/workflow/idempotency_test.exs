defmodule Athanor.Workflow.IdempotencyTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Instance
  alias Athanor.Workflow.Supervisor, as: WorkflowSupervisor

  setup do
    Application.put_env(:athanor, :dispatcher_impl, Athanor.Workflow.Dispatcher.StubDispatcher)
    :ok
  end

  test "workflow submission is idempotent at the supervisor level" do
    wid = Uniq.UUID.uuid7()

    assert {:ok, pid1} =
             DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid})

    # Second start attempt for the same workflow ID should return already_started
    result = DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid})
    assert {:error, {:already_started, ^pid1}} = result
  end
end
