defmodule Athanor.Workflow.DSLIntegrationTest do
  @moduledoc """
  Integration tests for parsing Starlark DSL fixtures, registering workflows,
  and asserting that the runtime state matches the parsed definitions.
  """

  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser
  alias Athanor.Workflow.Registry
  alias Athanor.Workflow.TaskMonitor

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  # ---------------------------------------------------------------------------
  # genomics_pipeline.star integration test
  # ---------------------------------------------------------------------------

  describe "genomics_pipeline.star end-to-end" do
    test "parses and registers workflow state correctly" do
      # 1. Parse the Starlark DSL
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))

      # Verify basic plan structure
      assert plan.name == "genomics_pipeline"
      assert length(plan.processes) == 3
      assert length(plan.channels) >= 2

      # Extract processes and channels for registration
      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      # 2. Start a workflow instance
      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      # 3. Register the workflow with the Registry
      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # 4. Assert subscriptions were derived correctly
      subscriptions = Registry.get_subscriptions(wid)
      assert is_map(subscriptions)

      # 5. Assert all processes are retrievable by ID
      for process <- plan.processes do
        registered_proc = Registry.get_process(wid, process.id)
        assert registered_proc != nil, "Process #{process.id} not found in registry"
        assert registered_proc.image == process.image.tag
        assert registered_proc.command == process.command
      end

      # 6. Assert all processes are retrievable by cosmetic name
      expected_names = ["align", "call_variants", "merge_vcfs"]

      for name <- expected_names do
        proc = Registry.get_process_by_name(wid, name)
        assert proc != nil, "Process with name '#{name}' not found"
        assert proc.name == name
      end

      # 7. Verify specific process details from the DSL
      align_proc = Registry.get_process_by_name(wid, "align")
      assert align_proc.image == "genomics/bwa:0.7.17"
      assert align_proc.command == "bwa mem -t {cpu} {ref} {reads} | samtools sort -o {output}"
      assert map_size(align_proc.input) == 2
      assert align_proc.input[:ref] != nil
      assert align_proc.input[:reads] != nil
      assert align_proc.resources.cpu == 8.0
      assert align_proc.resources.mem == 16.0
      assert align_proc.resources.disk == 50.0

      call_variants_proc = Registry.get_process_by_name(wid, "call_variants")
      assert call_variants_proc.image == "genomics/gatk:4.4"
      assert call_variants_proc.resources.cpu == 4.0
      assert call_variants_proc.resources.mem == 32.0
      assert call_variants_proc.resources.disk == 20.0

      merge_vcfs_proc = Registry.get_process_by_name(wid, "merge_vcfs")
      assert merge_vcfs_proc.image == "genomics/bcftools:1.18"
      assert merge_vcfs_proc.resources.cpu == 2.0
    end

    test "registers all channels with correct metadata" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      registered_channels = Registry.get_channels(wid)

      # Should have at least the literal and from_path channels declared in main()
      assert length(plan.channels) >= 2

      # All channels from the plan should be registered
      for channel <- plan.channels do
        assert registered_channels[channel.id] != nil, "Channel #{channel.id} not registered"
        assert registered_channels[channel.id].label == channel.id
        assert registered_channels[channel.id].type in [:path, :result, :literal]
      end
    end

    test "input-output wiring matches DSL declarations" do
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.star"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)
      subscriptions = Registry.get_subscriptions(wid)

      # Each process should be in subscriptions for its input channels
      for process <- plan.processes do
        proc = Registry.get_process(wid, process.id)

        for {_input_name, channel_id} <- proc.input do
          # This process should be listed as a subscriber to this channel
          assert process.id in subscriptions[channel_id] or subscriptions[channel_id] == nil,
                 "Process #{process.id} not subscribed to channel #{channel_id}"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # dynamic_split_align.star integration test
  # ---------------------------------------------------------------------------

  describe "dynamic_split_align.star end-to-end" do
    test "parses and registers workflow with glob outputs" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.star"))

      assert plan.name == "dynamic_split_align"
      assert length(plan.processes) == 2

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # Verify both processes are registered
      assert Registry.get_process_by_name(wid, "split_genome") != nil
      assert Registry.get_process_by_name(wid, "align_chunk") != nil

      # Verify split_genome has glob outputs
      split = Registry.get_process_by_name(wid, "split_genome")
      assert split.image == "genomics/tools:latest"
    end

    test "process names are correctly extracted from function calls" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.star"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # All process names should match the function names they were called from
      for process <- plan.processes do
        assert process.name in ["split_genome", "align_chunk"],
               "Unexpected process name: #{process.name}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases and failing validations integration test
  # ---------------------------------------------------------------------------

  describe "edge cases and failing scripts" do
    test "parsing fails and workflow registration is prevented for invalid scripts" do
      # Parsing should fail due to multiple validation errors
      result = Parser.parse(fixture("failing_validation.star"))

      assert {:error, msg} = result
      assert String.contains?(msg, "unknown_placeholder")
      assert String.contains?(msg, "unsupported URI scheme")
      assert String.contains?(msg, "resource 'cpu' must be > 0")

      # Since it returns an error, we don't proceed to register_workflow.
      # This confirms that invalid workflows don't reach the runtime.
    end

    test "mapping a channel with different output and input names resolves correctly" do
      {:ok, plan} = Parser.parse(fixture("channel_mapping.star"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      proc1 = Registry.get_process_by_name(wid, "process_one")
      proc2 = Registry.get_process_by_name(wid, "process_two")

      assert proc1 != nil
      assert proc2 != nil

      dsl_proc1 = Enum.find(plan.processes, &(&1.name == "process_one"))
      assert dsl_proc1.outputs.value[:out_val] == "s3://bucket/test.txt"

      assert String.starts_with?(proc2.input[:in2_val], "chan_")

      subscriptions = Registry.get_subscriptions(wid)

      proc2_internal_id =
        Enum.find_value(plan.processes, fn p ->
          if p.name == "process_two", do: p.id, else: nil
        end)

      proc2_id_in_subscriptions = subscriptions[proc2.input[:in2_val]] || []
      assert proc2_internal_id in proc2_id_in_subscriptions
    end
  end

  # ---------------------------------------------------------------------------
  # Reactive Glob DAG integration test
  # ---------------------------------------------------------------------------

  describe "reactive glob DAG execution setup" do
    test "processes can output globs and consumers subscribe to glob channels" do
      {:ok, plan} = Parser.parse(fixture("reactive_glob_dag.star"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(plan.channels, &{&1.id, %{label: &1.id, type: channel_type(&1.channel_type)}})

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # Validate producer outputs a glob
      producer = Enum.find(plan.processes, &(&1.name == "producer"))
      assert producer.outputs.type == "glob"
      assert producer.outputs.value == ["s3://bucket/out/*.txt"]

      # Validate consumer reads from the producer channel directly
      consumer = Registry.get_process_by_name(wid, "consumer")
      assert String.starts_with?(consumer.input[:input], "chan_")

      # Validate no channel from_path was generated (it was removed in the refactor)
      glob_channel = Enum.find(plan.channels, &(&1.channel_type == "path"))
      assert glob_channel == nil

      # Check subscriptions
      subscriptions = Registry.get_subscriptions(wid)

      consumer_id =
        Enum.find_value(plan.processes, fn p ->
          if p.name == "consumer", do: p.id, else: nil
        end)

      # The consumer should be subscribed to the producer's output channel
      assert consumer_id in (subscriptions[consumer.input[:input]] || [])
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp channel_type(:path), do: :path
  defp channel_type(:literal), do: :literal
  defp channel_type(:result), do: :result
  defp channel_type("path"), do: :path
  defp channel_type("literal"), do: :literal
  defp channel_type("result"), do: :result
  defp channel_type(other), do: other

  # Transform a process from the DSL parser (with :inputs, :outputs atom keys)
  # into the format expected by the Workflow.Registry (with :input key).
  #
  # The DSL parser returns a nested structure with atom keys (:inputs, :outputs, etc.)
  # while the runtime expects a flatter structure with :input (singular).
  defp dsl_process_to_runtime(dsl_proc) do
    %{
      name: dsl_proc.name,
      image: dsl_proc.image.tag,
      command: dsl_proc.command,
      input: dsl_proc.inputs || %{},
      output_search_patterns: [],
      resources: %{
        cpu: dsl_proc.resources.cpu,
        mem: dsl_proc.resources.mem,
        disk: dsl_proc.resources.disk
      },
      retry: dsl_proc[:retry]
    }
  end
end
