defmodule Athanor.Workflow.Registry do
  @moduledoc """
  Stores the definition of a single workflow instance: its channels, processes,
  and the derived subscription graph.

  A subscription is derived at registration time by inspecting each process's
  `input` map. For every `{_name, channel_id}` entry in `process.input`, the
  registry records that `process_id` subscribes to `channel_id`.

  The registry is intentionally read-heavy and write-light — the full
  graph is built once when the workflow is submitted, and subsequent reads
  (`get_subscriptions/1`, `get_process/2`) are used by the Scheduler during
  fan-out.

  ## Naming

      Athanor.Workflow.Registry.server_name(workflow_id)
  """

  use GenServer

  alias Athanor.Workflow

  # ---------------------------------------------------------------------------
  # Naming helpers
  # ---------------------------------------------------------------------------

  @spec server_name(Workflow.id()) :: {:global, String.t()}
  def server_name(workflow_id), do: {:global, "Athanor.Workflow.Registry.#{workflow_id}"}

  # ---------------------------------------------------------------------------
  # Child spec
  # ---------------------------------------------------------------------------

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
  # State types
  # ---------------------------------------------------------------------------

  @typep server_state :: %{
           workflow_id: Workflow.id(),
           # channel_id => channel metadata (type, label)
           channels: %{Workflow.channel_id() => channel_meta()},
           # process_id => process definition
           processes: %{Workflow.process_id() => Workflow.process()},
           # channel_id => [process_id]  (derived from process input maps)
           subscriptions: %{Workflow.channel_id() => [Workflow.process_id()]}
         }

  @type channel_meta :: %{
          label: String.t(),
          type: :literal | :path | :result
        }

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    GenServer.start_link(__MODULE__, opts, name: server_name(workflow_id))
  end

  @doc """
  Register the full workflow definition atomically.

  `channels` is a map of `channel_id => channel_meta`.
  `processes` is a map of `process_id => process`.

  Subscriptions are derived automatically from `process.input`.
  """
  @spec register_workflow(
          Workflow.id(),
          %{Workflow.channel_id() => channel_meta()},
          %{Workflow.process_id() => Workflow.process()}
        ) :: :ok
  def register_workflow(workflow_id, channels, processes) do
    GenServer.call(server_name(workflow_id), {:register_workflow, channels, processes})
  end

  @doc "Return all subscriptions as `channel_id => [process_id]`."
  @spec get_subscriptions(Workflow.id()) ::
          %{Workflow.channel_id() => [Workflow.process_id()]}
  def get_subscriptions(workflow_id) do
    GenServer.call(server_name(workflow_id), :get_subscriptions)
  end

  @doc "Fetch a single process definition by id, or `nil` if not registered."
  @spec get_process(Workflow.id(), Workflow.process_id()) :: Workflow.process() | nil
  def get_process(workflow_id, process_id) do
    GenServer.call(server_name(workflow_id), {:get_process, process_id})
  end

  @doc """
  Fetch a single process definition by name within a workflow, or `nil` if not found.

  Process names are cosmetic labels unique within a workflow. Returns `nil` if the
  name is not found or the workflow is not registered.
  """
  @spec get_process_by_name(Workflow.id(), String.t()) :: Workflow.process() | nil
  def get_process_by_name(workflow_id, name) do
    GenServer.call(server_name(workflow_id), {:get_process_by_name, name})
  end

  @doc "Fetch all registered channel metadata."
  @spec get_channels(Workflow.id()) :: %{Workflow.channel_id() => channel_meta()}
  def get_channels(workflow_id) do
    GenServer.call(server_name(workflow_id), :get_channels)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, server_state()}
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    {:ok,
     %{
       workflow_id: workflow_id,
       channels: %{},
       processes: %{},
       subscriptions: %{}
     }}
  end

  @impl true
  def handle_call({:register_workflow, channels, processes}, _from, state) do
    subscriptions = derive_subscriptions(processes)

    {:reply, :ok,
     %{state | channels: channels, processes: processes, subscriptions: subscriptions}}
  end

  def handle_call(:get_subscriptions, _from, state) do
    {:reply, state.subscriptions, state}
  end

  def handle_call({:get_process, process_id}, _from, state) do
    {:reply, Map.get(state.processes, process_id), state}
  end

  def handle_call({:get_process_by_name, name}, _from, state) do
    # Linear search through processes to find one with matching name.
    # Names are unique within a workflow, so we return the first match or nil.
    process =
      Enum.find_value(state.processes, nil, fn {_process_id, process} ->
        process.name == name && process
      end)

    {:reply, process, state}
  end

  def handle_call(:get_channels, _from, state) do
    {:reply, state.channels, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # Derive the subscription graph from process input declarations.
  # For each process, every value in `process.input` is a channel_id that the
  # process subscribes to.
  @spec derive_subscriptions(%{Workflow.process_id() => Workflow.process()}) ::
          %{Workflow.channel_id() => [Workflow.process_id()]}
  defp derive_subscriptions(processes) do
    Enum.reduce(processes, %{}, fn {process_id, process}, acc ->
      Enum.reduce(process.input, acc, fn {_name, channel_id}, subs ->
        Map.update(subs, channel_id, [process_id], &[process_id | &1])
      end)
    end)
  end
end
