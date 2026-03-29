defmodule Athanor.Workflow.Scheduler do
  @moduledoc """
  Reactive scheduler for a single workflow instance.

  Responsibilities:
  - Maintains per-channel append-only buffers (`IndexedBuffer`).
  - Tracks per-subscription cursors so each subscribing process receives every
    artifact independently (fan-out).
  - Deduplicates tasks via a content-addressable fingerprint index (CAS index)
    so the same (process + inputs) combination is never dispatched twice.
  - Delegates actual dispatch to a pluggable `Dispatcher` module (default:
    `StubDispatcher`).
  - Pull-based dispatch: the scheduler waits for demand before sending tasks to
    the dispatcher.

  ## Naming

  The scheduler is registered under a name derived from the `workflow_id` so
  multiple workflow instances can coexist in the same node:

      Athanor.Workflow.Scheduler.server_name(workflow_id)
  """

  use GenServer

  require Logger

  alias Athanor.IndexedBuffer
  alias Athanor.Workflow
  alias Athanor.Workflow.Dispatcher
  alias Athanor.Workflow.Fingerprinting
  alias Athanor.Workflow.TaskMonitor

  @type t :: GenServer.server()

  @spec server_name(Workflow.id()) :: {:global, String.t()}
  def server_name(workflow_id), do: {:global, "Athanor.Workflow.Scheduler.#{workflow_id}"}

  @typep state :: %{
           workflow_id: Workflow.id(),
           channels: %{Workflow.channel_id() => Workflow.channel()},
           zip_channels: %{
             Workflow.channel_id() => %{
               upstreams: [Workflow.channel_id()],
               cursor: non_neg_integer()
             }
           },
           processes: %{Workflow.process_id() => Workflow.process()},
           subscriptions: %{Workflow.channel_id() => [Workflow.subscription()]},
           running_tasks: %{Workflow.fingerprint() => Workflow.task()},
           cas_index: MapSet.t(Workflow.fingerprint()),
           queue: :queue.t()
         }

  @typep message ::
           {:register_process, Workflow.process_id(), Workflow.process()}
           | {:register_zip, Workflow.channel_id(), [Workflow.channel_id()]}
           | {:subscribe, Workflow.channel_id(), Workflow.process_id()}
           | {:publish, Workflow.channel_id(), [Workflow.artifact()]}
           | {:complete_task, Workflow.fingerprint(), [Workflow.artifact()]}
           | {:fail_task, Workflow.fingerprint()}
           | {:dispatch_next, pos_integer()}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    %{
      id: {__MODULE__, workflow_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    GenServer.start_link(__MODULE__, opts, name: server_name(workflow_id))
  end

  @doc """
  Register a process definition with an already-assigned `process_id`.
  The process is looked up by `process_id` when building job vouchers.
  """
  @spec register_process(t(), Workflow.process_id(), Workflow.process()) :: :ok
  def register_process(scheduler, process_id, process) do
    GenServer.cast(scheduler, {:register_process, process_id, process})
  end

  @doc """
  Register a zip channel with its upstream dependencies.
  """
  @spec register_zip(t(), Workflow.channel_id(), [Workflow.channel_id()]) :: :ok
  def register_zip(scheduler, zip_channel_id, upstreams) do
    GenServer.cast(scheduler, {:register_zip, zip_channel_id, upstreams})
  end

  @doc """
  Subscribe `process_id` to a channel. The subscription cursor starts at the
  current buffer length so only new arrivals trigger fan-out (use `0` if the
  process should also process items already in the buffer).
  """
  @spec subscribe(t(), Workflow.channel_id(), Workflow.process_id()) :: :ok
  def subscribe(scheduler, channel_id, process_id) do
    GenServer.cast(scheduler, {:subscribe, channel_id, process_id})
  end

  @doc """
  Publish one or more artifacts into a channel. Triggers fan-out synchronously
  inside the GenServer so cursors advance atomically with the append.
  """
  @spec publish(t(), Workflow.channel_id(), [Workflow.artifact()] | Workflow.artifact()) :: :ok
  def publish(scheduler, channel_id, artifacts)

  def publish(scheduler, channel_id, artifacts) when is_list(artifacts) do
    GenServer.cast(scheduler, {:publish, channel_id, artifacts})
  end

  def publish(scheduler, channel_id, artifact) do
    publish(scheduler, channel_id, [artifact])
  end

  @doc """
  Mark a running task as completed and publish its output artifacts to the
  process's output channel so downstream subscribers are triggered.
  """
  @spec complete_task(t(), Workflow.fingerprint(), [Workflow.artifact()]) :: :ok
  def complete_task(scheduler, fingerprint, output_artifacts \\ []) do
    GenServer.cast(scheduler, {:complete_task, fingerprint, output_artifacts})
  end

  @doc "Mark a running task as failed. It is removed from the running set."
  @spec fail_task(t(), Workflow.fingerprint()) :: :ok
  def fail_task(scheduler, fingerprint) do
    GenServer.cast(scheduler, {:fail_task, fingerprint})
  end

  @doc """
  Manually trigger dispatch with a specific demand.
  """
  @spec dispatch_next(t(), pos_integer()) :: :ok
  def dispatch_next(scheduler, demand \\ 1) do
    GenServer.cast(scheduler, {:dispatch_next, demand})
  end

  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    state = %{
      workflow_id: workflow_id,
      channels: %{},
      zip_channels: %{},
      processes: %{},
      subscriptions: %{},
      running_tasks: %{},
      cas_index: MapSet.new(),
      queue: :queue.new()
    }

    {:ok, state}
  end

  @impl true
  @spec handle_cast(message(), state()) :: {:noreply, state()}
  def handle_cast({:register_process, process_id, process}, state) do
    {:noreply, %{state | processes: Map.put(state.processes, process_id, process)}}
  end

  def handle_cast({:register_zip, zip_channel_id, upstreams}, state) do
    zip_state = %{upstreams: upstreams, cursor: 0}
    {:noreply, %{state | zip_channels: Map.put(state.zip_channels, zip_channel_id, zip_state)}}
  end

  def handle_cast({:subscribe, channel_id, process_id}, state) do
    # Cursor starts at current buffer length — only future arrivals trigger tasks.
    # Callers that want to reprocess existing items should call publish/3 explicitly.

    already_subscribed? =
      state.subscriptions
      |> Map.get(channel_id, [])
      |> Enum.any?(fn sub -> sub.process_id == process_id end)

    if already_subscribed? do
      {:noreply, state}
    else
      current_count =
        case Map.get(state.channels, channel_id) do
          nil -> 0
          ch -> ch.buf.count
        end

      subscription = %{cursor: current_count, process_id: process_id}

      subscriptions =
        Map.update(state.subscriptions, channel_id, [subscription], &[subscription | &1])

      {:noreply, %{state | subscriptions: subscriptions}}
    end
  end

  def handle_cast({:publish, channel_id, artifacts}, state) do
    state
    |> do_append(channel_id, artifacts)
    |> evaluate_zips(channel_id)
    |> fan_out(channel_id)
    |> do_dispatch_next(1)
    |> then(&{:noreply, &1})
  end

  def handle_cast({:complete_task, fingerprint, output_artifacts}, state) do
    case Map.pop(state.running_tasks, fingerprint) do
      {nil, _} ->
        Logger.warning("[Scheduler] complete_task called for unknown fingerprint #{fingerprint}")
        {:noreply, state}

      {task, running_tasks} ->
        Logger.info("[Scheduler] task completed", fingerprint: fingerprint)
        state = %{state | running_tasks: running_tasks}
        TaskMonitor.unregister(state.workflow_id, fingerprint)

        # Publish output artifacts so downstream subscribers are triggered
        state =
          if output_artifacts != [] do
            # Output channel id is keyed by process_id for Phase 1.
            # Phase 4 (AZ-401) will use named output channels from the Registry.
            output_channel_id = task.process_id

            do_append(state, output_channel_id, output_artifacts)
            |> evaluate_zips(output_channel_id)
            |> fan_out(output_channel_id)
          else
            state
          end

        state |> do_dispatch_next(1) |> then(&{:noreply, &1})
    end
  end

  def handle_cast({:fail_task, fingerprint}, state) do
    case Map.pop(state.running_tasks, fingerprint) do
      {nil, _} ->
        Logger.warning("[Scheduler] fail_task called for unknown fingerprint #{fingerprint}")
        {:noreply, state}

      {_task, running_tasks} ->
        Logger.warning("[Scheduler] task failed", fingerprint: fingerprint)
        state = %{state | running_tasks: running_tasks}
        TaskMonitor.unregister(state.workflow_id, fingerprint)
        state |> do_dispatch_next(1) |> then(&{:noreply, &1})
    end
  end

  def handle_cast({:dispatch_next, demand}, state) do
    {:noreply, do_dispatch_next(state, demand)}
  end

  @spec do_append(state(), Workflow.channel_id(), [Workflow.artifact()] | [[Workflow.artifact()]]) ::
          state()
  defp do_append(state, channel_id, artifacts) do
    channel = Map.get(state.channels, channel_id, %{buf: IndexedBuffer.new(), closed?: false})
    buf = IndexedBuffer.append(channel.buf, artifacts)
    channels = Map.put(state.channels, channel_id, %{channel | buf: buf})
    %{state | channels: channels}
  end

  @spec evaluate_zips(state(), Workflow.channel_id()) :: state()
  defp evaluate_zips(state, channel_id) do
    dependent_zips =
      state.zip_channels
      |> Enum.filter(fn {_zip_id, zip_state} -> channel_id in zip_state.upstreams end)
      |> Enum.map(fn {zip_id, _zip_state} -> zip_id end)

    Enum.reduce(dependent_zips, state, fn zip_id, acc_state ->
      try_pull_zip(acc_state, zip_id)
    end)
  end

  defp try_pull_zip(state, zip_id) do
    zip_state = Map.fetch!(state.zip_channels, zip_id)
    cursor = zip_state.cursor

    all_ready? =
      Enum.all?(zip_state.upstreams, fn up_id ->
        channel = Map.get(state.channels, up_id)
        channel != nil and channel.buf.count > cursor
      end)

    if all_ready? do
      zipped_item =
        Enum.map(zip_state.upstreams, fn up_id ->
          channel = Map.fetch!(state.channels, up_id)
          IndexedBuffer.at(channel.buf, cursor)
        end)

      updated_zip_state = %{zip_state | cursor: cursor + 1}

      state_with_cursor = %{
        state
        | zip_channels: Map.put(state.zip_channels, zip_id, updated_zip_state)
      }

      state_with_cursor
      |> do_append(zip_id, [zipped_item])
      # Cascading zips if zip channels depend on zip channels
      |> evaluate_zips(zip_id)
      |> fan_out(zip_id)
      |> try_pull_zip(zip_id)
    else
      state
    end
  end

  # For each subscription on `channel_id`, collect items since the subscription's
  # cursor and enqueue one task per artifact (if not already in the CAS index).
  @spec fan_out(state(), Workflow.channel_id()) :: state()
  defp fan_out(state, channel_id) do
    subscriptions = Map.get(state.subscriptions, channel_id, [])
    channel = Map.get(state.channels, channel_id)

    if channel == nil or subscriptions == [] do
      state
    else
      {updated_subscriptions, state} =
        Enum.map_reduce(subscriptions, state, fn subscription, acc ->
          new_items = IndexedBuffer.from_cursor(channel.buf, subscription.cursor)

          acc =
            Enum.reduce(new_items, acc, fn artifact, s ->
              enqueue_if_new(s, subscription.process_id, artifact)
            end)

          updated_sub = %{subscription | cursor: subscription.cursor + length(new_items)}
          {updated_sub, acc}
        end)

      updated_subs_map = Map.put(state.subscriptions, channel_id, updated_subscriptions)
      %{state | subscriptions: updated_subs_map}
    end
  end

  # Build a task for (process_id, artifact) and enqueue it unless the CAS index
  # already has an entry for the fingerprint (deduplication).
  @spec enqueue_if_new(
          state(),
          Workflow.process_id(),
          Workflow.artifact() | [Workflow.artifact()]
        ) :: state()
  defp enqueue_if_new(state, process_id, artifact_or_artifacts) do
    process = Map.get(state.processes, process_id)

    if process == nil do
      Logger.warning("[Scheduler] fan_out skipping unknown process_id #{inspect(process_id)}")

      state
    else
      flat_artifacts = List.flatten(List.wrap(artifact_or_artifacts))

      task_info = %{
        process_image: process.image,
        resolved_command: process.command,
        output_search_patterns: process.output_search_patterns,
        input_artifacts: flat_artifacts,
        output_artifacts: []
      }

      fingerprint = Fingerprinting.fingerprint(task_info)

      if MapSet.member?(state.cas_index, fingerprint) do
        # Already dispatched or queued — idempotent, skip.
        state
      else
        task = %{
          process_id: process_id,
          status: :pending,
          fingerprint: fingerprint,
          input_artifacts: flat_artifacts,
          output_artifacts: []
        }

        %{
          state
          | queue: :queue.snoc(state.queue, task),
            cas_index: MapSet.put(state.cas_index, fingerprint)
        }
      end
    end
  end

  # Drain the queue up to `demand`, dispatching one task per slot.
  defp do_dispatch_next(state, demand) do
    if demand <= 0 or :queue.is_empty(state.queue) do
      state
    else
      {{:value, task}, queue} = :queue.out(state.queue)
      state = %{state | queue: queue}

      process = Map.fetch!(state.processes, task.process_id)
      voucher = Dispatcher.build_voucher(state.workflow_id, task, process)

      case Dispatcher.dispatch(voucher) do
        {:ok, _ref} ->
          running_task = %{task | status: :running}

          state = %{
            state
            | running_tasks: Map.put(state.running_tasks, task.fingerprint, running_task)
          }

          # Continue draining — recurse until demand met or empty
          do_dispatch_next(state, demand - 1)

        {:error, reason} ->
          Logger.error("[Scheduler] dispatch failed for #{task.fingerprint}: #{inspect(reason)}")

          # Re-enqueue at the back so it can be retried; remove from CAS so it
          # can be re-fingerprinted if inputs change. Phase 5 adds backoff.
          state = %{
            state
            | queue: :queue.snoc(state.queue, task),
              cas_index: MapSet.delete(state.cas_index, task.fingerprint)
          }

          # Try next in queue for this demand slot
          do_dispatch_next(state, demand)
      end
    end
  end
end
