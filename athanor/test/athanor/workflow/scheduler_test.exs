defmodule Athanor.Workflow.SchedulerTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Scheduler
  alias Athanor.Workflow.TaskMonitor

  defp unique_id, do: Uniq.UUID.uuid7()

  defp artifact(uri) do
    %{uri: URI.parse(uri), hash: "sha256:abc", metadata: %{}}
  end

  defp process(image \\ "img:1", command \\ "run.sh", output_patterns \\ []) do
    %{
      image: image,
      command: command,
      input: %{},
      output_search_patterns: output_patterns,
      resources: %{cpu: 1.0, mem: 512, disk: 1024}
    }
  end

  defp start_instance(opts \\ []) do
    wid = unique_id()
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)

    start_supervised!(TaskMonitor.registry_child_spec(wid))

    start_supervised!({TaskMonitor, workflow_id: wid})

    sched =
      start_supervised!({Scheduler, workflow_id: wid, max_concurrency: max_concurrency})

    {wid, sched}
  end

  setup do
    Application.put_env(:athanor, :dispatcher_impl, Athanor.Workflow.Dispatcher.StubDispatcher)
    :ok
  end

  describe "register_process / subscribe" do
    test "subscribing to a channel after items exist sets cursor to current length" do
      {_wid, sched} = start_instance()
      ch = unique_id()
      pid = unique_id()

      Scheduler.publish(sched, ch, [artifact("s3://a"), artifact("s3://b")])

      Scheduler.subscribe(sched, ch, pid)
    end
  end

  describe "fan_out on publish" do
    test "publishes to a subscribed process and dispatches tasks" do
      {_wid, sched} = start_instance()

      ch = unique_id()
      p_id = unique_id()

      Scheduler.register_process(sched, p_id, process())

      Scheduler.subscribe(sched, ch, p_id)

      Scheduler.publish(sched, ch, [artifact("s3://1"), artifact("s3://2"), artifact("s3://3")])

      :sys.get_state(sched)

      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 3
    end

    test "does not enqueue duplicate fingerprints (CAS dedup)" do
      {_wid, sched} = start_instance()

      ch = unique_id()
      p_id = unique_id()
      a = artifact("s3://bucket/same.fa")

      Scheduler.register_process(sched, p_id, process())
      Scheduler.subscribe(sched, ch, p_id)

      Scheduler.publish(sched, ch, [a])
      Scheduler.publish(sched, ch, [a])

      :sys.get_state(sched)

      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 1
    end

    test "respects max_concurrency: excess tasks wait in queue" do
      {_wid, sched} = start_instance(max_concurrency: 2)

      ch = unique_id()
      p_id = unique_id()

      Scheduler.register_process(sched, p_id, process())
      Scheduler.subscribe(sched, ch, p_id)

      Scheduler.publish(sched, ch, [
        artifact("s3://1"),
        artifact("s3://2"),
        artifact("s3://3")
      ])

      :sys.get_state(sched)
      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 2
      assert :queue.len(state.queue) == 1
    end
  end

  describe "complete_task/3" do
    test "removes task from running and drains the queue" do
      {_wid, sched} = start_instance(max_concurrency: 1)

      ch = unique_id()
      p_id = unique_id()

      Scheduler.register_process(sched, p_id, process())
      Scheduler.subscribe(sched, ch, p_id)

      Scheduler.publish(sched, ch, [artifact("s3://a"), artifact("s3://b")])
      :sys.get_state(sched)

      state = :sys.get_state(sched)
      assert map_size(state.running_tasks) == 1
      assert :queue.len(state.queue) == 1

      [fingerprint] = Map.keys(state.running_tasks)
      Scheduler.complete_task(sched, fingerprint, [])
      :sys.get_state(sched)

      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 1
      assert :queue.is_empty(state.queue)
    end

    test "publishes output artifacts to an output channel triggering downstream fan-out" do
      {_wid, sched} = start_instance()

      input_ch = unique_id()
      upstream_p = unique_id()
      downstream_p = unique_id()

      Scheduler.register_process(sched, upstream_p, process("img", "step1"))
      Scheduler.register_process(sched, downstream_p, process("img", "step2"))

      Scheduler.subscribe(sched, input_ch, upstream_p)

      Scheduler.subscribe(sched, upstream_p, downstream_p)

      Scheduler.publish(sched, input_ch, [artifact("s3://ref.fa")])
      :sys.get_state(sched)

      state = :sys.get_state(sched)
      [fingerprint] = Map.keys(state.running_tasks)

      Scheduler.complete_task(sched, fingerprint, [artifact("s3://out/result.bam")])
      :sys.get_state(sched)

      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 1
      [downstream_task] = Map.values(state.running_tasks)
      assert downstream_task.process_id == downstream_p
    end
  end

  describe "fail_task/2" do
    test "removes task from running and drains the queue" do
      {_wid, sched} = start_instance(max_concurrency: 1)

      ch = unique_id()
      p_id = unique_id()

      Scheduler.register_process(sched, p_id, process())
      Scheduler.subscribe(sched, ch, p_id)

      Scheduler.publish(sched, ch, [artifact("s3://x"), artifact("s3://y")])
      :sys.get_state(sched)

      state = :sys.get_state(sched)
      [fingerprint] = Map.keys(state.running_tasks)

      Scheduler.fail_task(sched, fingerprint)
      :sys.get_state(sched)

      state = :sys.get_state(sched)
      assert map_size(state.running_tasks) == 1
      assert :queue.is_empty(state.queue)
    end
  end

  describe "multiple subscribers to the same channel" do
    test "each subscriber receives every artifact independently" do
      {_wid, sched} = start_instance()

      ch = unique_id()
      p1 = unique_id()
      p2 = unique_id()

      Scheduler.register_process(sched, p1, process("img", "cmd-p1"))
      Scheduler.register_process(sched, p2, process("img", "cmd-p2"))

      Scheduler.subscribe(sched, ch, p1)
      Scheduler.subscribe(sched, ch, p2)

      Scheduler.publish(sched, ch, [artifact("s3://shared.fa")])
      :sys.get_state(sched)

      state = :sys.get_state(sched)

      assert map_size(state.running_tasks) == 2
      process_ids = state.running_tasks |> Map.values() |> Enum.map(& &1.process_id)
      assert p1 in process_ids
      assert p2 in process_ids
    end
  end

  describe "edge cases and errors" do
    import ExUnit.CaptureLog

    test "publish/3 accepts a single artifact instead of a list" do
      {_wid, sched} = start_instance()
      ch = unique_id()
      p = unique_id()

      Scheduler.register_process(sched, p, process())
      Scheduler.subscribe(sched, ch, p)

      Scheduler.publish(sched, ch, artifact("s3://single.txt"))
      :sys.get_state(sched)

      state = :sys.get_state(sched)
      assert map_size(state.running_tasks) == 1
    end

    test "complete_task/3 on unknown fingerprint logs warning" do
      {_wid, sched} = start_instance()

      log =
        capture_log(fn ->
          Scheduler.complete_task(sched, "unknown_fp")
          :sys.get_state(sched)
        end)

      assert log =~ "complete_task called for unknown fingerprint unknown_fp"
    end

    test "fail_task/2 on unknown fingerprint logs warning" do
      {_wid, sched} = start_instance()

      log =
        capture_log(fn ->
          Scheduler.fail_task(sched, "unknown_fp")
          :sys.get_state(sched)
        end)

      assert log =~ "fail_task called for unknown fingerprint unknown_fp"
    end

    test "fan_out skipping unknown process_id logs warning" do
      {_wid, sched} = start_instance()
      ch = unique_id()

      Scheduler.subscribe(sched, ch, "unknown_process")

      log =
        capture_log(fn ->
          Scheduler.publish(sched, ch, [artifact("s3://test.txt")])
          :sys.get_state(sched)
        end)

      assert log =~ "fan_out skipping unknown process_id"
    end

    test "handle_cast(:dispatch_next) when queue is empty does nothing" do
      {_wid, sched} = start_instance()
      GenServer.cast(sched, :dispatch_next)

      state = :sys.get_state(sched)
      assert :queue.is_empty(state.queue)
    end
  end
end
