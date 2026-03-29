defmodule Athanor.Workflow.RegistryTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Registry, as: WorkflowRegistry

  defp unique_id, do: Uniq.UUID.uuid7()

  defp start_registry(workflow_id) do
    start_supervised!({WorkflowRegistry, workflow_id: workflow_id})
  end

  defp channel_meta(label, type \\ :result),
    do: %{label: label, type: type}

  defp process(image, command, input_map, output_patterns \\ []) do
    %{
      name: "process_#{:rand.uniform(100_000)}",
      image: image,
      command: command,
      input: input_map,
      output_search_patterns: output_patterns,
      resources: %{cpu: 1.0, mem: 512, disk: 1024}
    }
  end

  describe "register_workflow/3 and get_subscriptions/1" do
    test "derives subscriptions from process input declarations" do
      wid = unique_id()
      start_registry(wid)

      ch1 = unique_id()
      ch2 = unique_id()
      p1 = unique_id()
      p2 = unique_id()

      channels = %{ch1 => channel_meta("ch1"), ch2 => channel_meta("ch2")}

      processes = %{
        p1 => process("img", "cmd", %{"in" => %{channel_id: ch1, format: "generic"}}),
        p2 =>
          process("img", "cmd", %{
            "a" => %{channel_id: ch1, format: "generic"},
            "b" => %{channel_id: ch2, format: "generic"}
          })
      }

      :ok = WorkflowRegistry.register_workflow(wid, channels, processes)

      subs = WorkflowRegistry.get_subscriptions(wid)

      assert p1 in subs[ch1]
      assert p2 in subs[ch1]
      assert p2 in subs[ch2]
      refute Map.has_key?(subs, unique_id())
    end

    test "a process with no inputs produces no subscriptions" do
      wid = unique_id()
      start_registry(wid)
      p = unique_id()

      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{p => process("img", "cmd", %{})})

      assert WorkflowRegistry.get_subscriptions(wid) == %{}
    end

    test "re-registering overwrites the previous state" do
      wid = unique_id()
      start_registry(wid)
      ch = unique_id()
      p = unique_id()

      :ok =
        WorkflowRegistry.register_workflow(wid, %{ch => channel_meta("ch")}, %{
          p => process("img", "cmd", %{"in" => %{channel_id: ch, format: "generic"}})
        })

      assert p in WorkflowRegistry.get_subscriptions(wid)[ch]

      # Re-register with empty maps
      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{})
      assert WorkflowRegistry.get_subscriptions(wid) == %{}
    end
  end

  describe "get_process/2" do
    test "returns the process definition for a known id" do
      wid = unique_id()
      start_registry(wid)
      p = unique_id()
      proc = process("my/image:1", "run.sh", %{})

      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{p => proc})

      assert WorkflowRegistry.get_process(wid, p) == proc
    end

    test "returns nil for an unknown process_id" do
      wid = unique_id()
      start_registry(wid)
      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{})

      assert WorkflowRegistry.get_process(wid, unique_id()) == nil
    end
  end

  describe "get_channels/1" do
    test "returns registered channel metadata" do
      wid = unique_id()
      start_registry(wid)
      ch = unique_id()
      meta = channel_meta("samples", :path)

      :ok = WorkflowRegistry.register_workflow(wid, %{ch => meta}, %{})
      assert WorkflowRegistry.get_channels(wid) == %{ch => meta}
    end
  end

  describe "get_process_by_name/2" do
    test "returns the process definition for a known name" do
      wid = unique_id()
      start_registry(wid)
      p = unique_id()
      proc = %{process("my/image:1", "run.sh", %{}) | name: "align"}

      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{p => proc})

      assert WorkflowRegistry.get_process_by_name(wid, "align") == proc
    end

    test "returns nil for an unknown process name" do
      wid = unique_id()
      start_registry(wid)
      p = unique_id()
      proc = %{process("my/image:1", "run.sh", %{}) | name: "align"}

      :ok = WorkflowRegistry.register_workflow(wid, %{}, %{p => proc})

      assert WorkflowRegistry.get_process_by_name(wid, "unknown") == nil
    end

    test "returns correct process when multiple processes exist" do
      wid = unique_id()
      start_registry(wid)
      p1 = unique_id()
      p2 = unique_id()
      p3 = unique_id()

      proc1 = %{process("img:1", "cmd", %{}) | name: "align"}
      proc2 = %{process("img:2", "cmd", %{}) | name: "call_variants"}
      proc3 = %{process("img:3", "cmd", %{}) | name: "merge"}

      :ok =
        WorkflowRegistry.register_workflow(
          wid,
          %{},
          %{p1 => proc1, p2 => proc2, p3 => proc3}
        )

      assert WorkflowRegistry.get_process_by_name(wid, "call_variants") == proc2
      assert WorkflowRegistry.get_process_by_name(wid, "align") == proc1
      assert WorkflowRegistry.get_process_by_name(wid, "merge") == proc3
    end
  end

  describe "not found cases" do
    test "returns defaults when workflow is not found" do
      bad_id = "unknown_workflow"
      assert WorkflowRegistry.get_subscriptions(bad_id) == %{}
      assert WorkflowRegistry.get_process(bad_id, "any") == nil
      assert WorkflowRegistry.get_process_by_name(bad_id, "any") == nil
      assert WorkflowRegistry.get_channels(bad_id) == %{}
    end
  end
end
