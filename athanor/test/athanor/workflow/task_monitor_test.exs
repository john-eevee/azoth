defmodule Athanor.Workflow.TaskMonitorTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.TaskMonitor

  setup do
    workflow_id = "test_monitor_#{System.unique_integer([:positive])}"
    start_supervised!(TaskMonitor.registry_child_spec(workflow_id))
    pid = start_supervised!(TaskMonitor.child_spec(workflow_id: workflow_id))
    %{workflow_id: workflow_id, monitor: pid}
  end

  test "registers a task and handles clean unregister", %{
    workflow_id: workflow_id,
    monitor: monitor
  } do
    task_pid = spawn(fn -> Process.sleep(5000) end)
    scheduler_pid = self()
    TaskMonitor.register(workflow_id, "fp1", task_pid, scheduler_pid)
    :sys.get_state(monitor)
    assert TaskMonitor.lookup(workflow_id, "fp1") == monitor
    TaskMonitor.unregister(workflow_id, "fp1")
    :sys.get_state(monitor)
    assert TaskMonitor.lookup(workflow_id, "fp1") == nil
  end

  test "unregister does nothing if fingerprint not found", %{
    workflow_id: workflow_id,
    monitor: monitor
  } do
    TaskMonitor.unregister(workflow_id, "fp_unknown")
    :sys.get_state(monitor)
    assert TaskMonitor.lookup(workflow_id, "fp_unknown") == nil
  end

  test "handles unexpected task crash (DOWN with reason != :normal)", %{
    workflow_id: workflow_id,
    monitor: monitor
  } do
    scheduler_pid = self()
    task_pid = spawn(fn -> exit(:boom) end)
    TaskMonitor.register(workflow_id, "fp2", task_pid, scheduler_pid)
    assert_receive {:"$gen_cast", {:fail_task, "fp2"}}, 1000
    :sys.get_state(monitor)
    assert TaskMonitor.lookup(workflow_id, "fp2") == nil
  end

  test "handles expected task completion (DOWN with reason == :normal)", %{
    workflow_id: workflow_id,
    monitor: monitor
  } do
    scheduler_pid = self()

    task_pid =
      spawn(fn ->
        receive do
          :exit -> exit(:normal)
        end
      end)

    TaskMonitor.register(workflow_id, "fp3", task_pid, scheduler_pid)
    :sys.get_state(monitor)
    send(task_pid, :exit)
    refute_receive {:"$gen_cast", {:fail_task, "fp3"}}, 100
    :sys.get_state(monitor)
    assert TaskMonitor.lookup(workflow_id, "fp3") == nil
  end

  test "handles DOWN for unknown monitor ref", %{monitor: monitor} do
    ref = make_ref()
    send(monitor, {:DOWN, ref, :process, self(), :boom})
    assert is_map(:sys.get_state(monitor))
  end
end
