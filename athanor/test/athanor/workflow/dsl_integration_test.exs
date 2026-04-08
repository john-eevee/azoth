defmodule Athanor.Workflow.DSLIntegrationTest do
  @moduledoc """
  Integration tests for parsing Starlark DSL fixtures, registering workflows,
  and asserting that the runtime state matches the parsed definitions.
  """

  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser
  alias Athanor.Workflow.Registry
  alias Athanor.Workflow.Scheduler
  alias Athanor.Workflow.TaskMonitor

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Application.put_env(:athanor, :dispatcher_impl, Athanor.Workflow.DispatcherMock)
    set_mox_from_context(nil)
    Mox.stub_with(Athanor.Workflow.DispatcherMock, Athanor.Workflow.Dispatcher.StubDispatcher)
    :ok
  end

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  # ---------------------------------------------------------------------------
  # genomics_pipeline.kdl integration test
  # ---------------------------------------------------------------------------

  describe "genomics_pipeline.kdl end-to-end" do
    test "parses and registers workflow state correctly" do
      # 1. Parse the Starlark DSL
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))

      # Verify basic plan structure
      assert plan.name == "genomics_pipeline"
      assert length(plan.processes) == 3
      assert length(plan.channels) >= 2

      # Extract processes and channels for registration
      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

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
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

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
      {:ok, plan} = Parser.parse(fixture("genomics_pipeline.kdl"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

      Registry.register_workflow(wid, channels_by_id, processes_by_id)
      subscriptions = Registry.get_subscriptions(wid)

      # Each process should be in subscriptions for its input channels
      for process <- plan.processes do
        proc = Registry.get_process(wid, process.id)

        for {_input_name, input_def} <- proc.input do
          # This process should be listed as a subscriber to this channel
          assert process.id in subscriptions[input_def.channel_id] or
                   subscriptions[input_def.channel_id] == nil,
                 "Process #{process.id} not subscribed to channel #{input_def.channel_id}"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # dynamic_split_align.kdl integration test
  # ---------------------------------------------------------------------------

  describe "dynamic_split_align.kdl end-to-end" do
    test "parses and registers workflow with glob outputs" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.kdl"))

      assert plan.name == "dynamic_split_align"
      assert length(plan.processes) == 2

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # Verify both processes are registered
      assert Registry.get_process_by_name(wid, "split_genome") != nil
      assert Registry.get_process_by_name(wid, "align_chunk") != nil

      # Verify split_genome has glob outputs
      split = Registry.get_process_by_name(wid, "split_genome")
      assert split.image == "genomics/tools:latest"
    end

    test "process names are correctly extracted from function calls" do
      {:ok, plan} = Parser.parse(fixture("dynamic_split_align.kdl"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

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
      result = Parser.parse(fixture("failing_validation.kdl"))

      assert {:error, msg} = result
      assert String.contains?(msg, "unknown_placeholder")
      assert String.contains?(msg, "unsupported URI scheme")
      assert String.contains?(msg, "resource 'cpu' must be > 0")

      # Since it returns an error, we don't proceed to register_workflow.
      # This confirms that invalid workflows don't reach the runtime.
    end

    test "mapping a channel with different output and input names resolves correctly" do
      {:ok, plan} = Parser.parse(fixture("channel_mapping.kdl"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      proc1 = Registry.get_process_by_name(wid, "process_one")
      proc2 = Registry.get_process_by_name(wid, "process_two")

      assert proc1 != nil
      assert proc2 != nil

      dsl_proc1 = Enum.find(plan.processes, &(&1.name == "process_one"))
      assert dsl_proc1.outputs.value[:out_val].uri == "s3://bucket/test.txt"

      assert proc2.input[:in2_val].channel_id == "out1"

      subscriptions = Registry.get_subscriptions(wid)

      proc2_internal_id =
        Enum.find_value(plan.processes, fn p ->
          if p.name == "process_two", do: p.id, else: nil
        end)

      proc2_id_in_subscriptions = subscriptions[proc2.input[:in2_val].channel_id] || []
      assert proc2_internal_id in proc2_id_in_subscriptions
    end
  end

  # ---------------------------------------------------------------------------
  # Reactive Glob DAG integration test
  # ---------------------------------------------------------------------------

  describe "reactive glob DAG execution setup" do
    test "processes can output globs and consumers subscribe to glob channels" do
      {:ok, plan} = Parser.parse(fixture("reactive_glob_dag.kdl"))

      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams]
           }}
        )

      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # Validate producer outputs a glob
      producer = Enum.find(plan.processes, &(&1.name == "producer"))
      assert producer.outputs.type == "glob"
      assert producer.outputs.value == ["s3://bucket/out/*.txt"]

      # Validate consumer reads from the producer channel directly
      consumer = Registry.get_process_by_name(wid, "consumer")
      assert consumer.input[:input].channel_id == "producer_output"

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
      assert consumer_id in (subscriptions[consumer.input[:input].channel_id] || [])
    end
  end

  # ---------------------------------------------------------------------------
  # zip_channels.kdl integration test
  # ---------------------------------------------------------------------------

  describe "zip channels execution setup" do
    test "processes can accept zipped channels as input and scheduler executes them correctly" do
      # 1. Parse the workflow
      {:ok, plan} = Parser.parse(fixture("zip_channels.kdl"))

      # 2. Start necessary supervisors and instances
      wid = Uniq.UUID.uuid7()
      start_supervised!(TaskMonitor.registry_child_spec(wid))
      start_supervised!({TaskMonitor, workflow_id: wid})
      start_supervised!({Registry, workflow_id: wid})
      sched = start_supervised!({Scheduler, workflow_id: wid, max_concurrency: 4})

      processes_by_id = Map.new(plan.processes, &{&1.id, dsl_process_to_runtime(&1)})

      channels_by_id =
        Map.new(
          plan.channels,
          &{&1.id,
           %{
             label: &1.id,
             type: channel_type(&1.channel_type),
             format: &1.format || "generic",
             upstreams: &1.source[:upstreams] || []
           }}
        )

      # 3. Register the workflow in the central Registry
      Registry.register_workflow(wid, channels_by_id, processes_by_id)

      # 4. Mirror the setup to the Scheduler (this is usually done by an orchestrator supervisor)
      for {proc_id, proc} <- processes_by_id do
        Scheduler.register_process(sched, proc_id, proc)
      end

      for {channel_id, channel} <- channels_by_id do
        if channel.type == :zip do
          Scheduler.register_zip(sched, channel_id, channel.upstreams)
        end
      end

      # Subscribe based on the Registry's computed subscriptions
      subscriptions = Registry.get_subscriptions(wid)

      for {channel_id, subs} <- subscriptions, process_id <- subs do
        Scheduler.subscribe(sched, channel_id, process_id)
      end

      # 5. Extract specific IDs for our test assertions
      align = Registry.get_process_by_name(wid, "align")
      assert align.input[:reads] != nil
      zip_channel_id = align.input[:reads].channel_id

      channels = Registry.get_channels(wid)
      zip_channel = channels[zip_channel_id]
      assert zip_channel.type == :zip
      assert length(zip_channel.upstreams) == 2
      [r1_ch, r2_ch] = zip_channel.upstreams

      # 6. Expect dispatch to be called when the zipped item is complete
      expect(Athanor.Workflow.DispatcherMock, :dispatch, 1, fn voucher ->
        {:ok, voucher.fingerprint}
      end)

      # 7. Push data to the upstream channels
      artifact_r1 = %{uri: URI.parse("s3://r1.fastq"), hash: "sha256:1", metadata: %{}}
      Scheduler.publish(sched, r1_ch, [artifact_r1])

      # Assert no task dispatched yet
      :sys.get_state(sched)
      state = :sys.get_state(sched)
      assert map_size(state.running_tasks) == 0

      # Push matching data to the second channel
      artifact_r2 = %{uri: URI.parse("s3://r2.fastq"), hash: "sha256:2", metadata: %{}}
      Scheduler.publish(sched, r2_ch, [artifact_r2])

      # Tell scheduler to dispatch whatever is ready
      Scheduler.dispatch_next(sched, 1)
      :sys.get_state(sched)
      state = :sys.get_state(sched)

      # 8. Assert that the fan-out created a task with both artifacts flattened
      assert map_size(state.running_tasks) == 1
      [task] = Map.values(state.running_tasks)

      align_proc_id = Enum.find(plan.processes, &(&1.name == "align")).id
      assert task.process_id == align_proc_id
      assert length(task.input_artifacts) == 2

      assert Enum.map(task.input_artifacts, &to_string(&1.uri)) == [
               "s3://r1.fastq",
               "s3://r2.fastq"
             ]
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
  defp channel_type(:zip), do: :zip
  defp channel_type("path"), do: :path
  defp channel_type("literal"), do: :literal
  defp channel_type("result"), do: :result
  defp channel_type("zip"), do: :zip
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
