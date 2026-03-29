defmodule Athanor.Workflow.Registry do
  @moduledoc """
  Stores the definition of a single workflow instance: its channels, processes,
  and the derived subscription graph.

  The registry is designed to be read-heavy and write-light. To avoid mailbox
  bottlenecks and atom/table exhaustion, all workflow instances store their
  data in a single global, public ETS table (`:athanor_workflows`) keyed by `workflow_id`.

  ## Naming

      Athanor.Workflow.Registry.via_name(workflow_id)
  """

  use GenServer, restart: :permanent

  alias Athanor.Workflow

  @table :athanor_workflows

  @spec via_name(Workflow.id()) :: {:via, Registry, {Athanor.Workflow.Registry, String.t()}}
  def via_name(workflow_id),
    do: {:via, Registry, {Athanor.Workflow.Registry, "registry:#{workflow_id}"}}

  @typep server_state :: %{
           workflow_id: Workflow.id()
         }

  @type channel_meta :: %{
          label: String.t(),
          type: :literal | :path | :result | :zip,
          format: String.t(),
          upstreams: [Workflow.channel_id()] | nil
        }

  defmodule WorkflowData do
    @moduledoc false
    defstruct channels: %{}, processes: %{}, subscriptions: %{}, names_index: %{}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(workflow_id))
  end

  @doc """
  Register the full workflow definition atomically.

  Subscriptions are derived automatically from `process.input`.
  """
  @spec register_workflow(
          Workflow.id(),
          %{Workflow.channel_id() => channel_meta()},
          %{Workflow.process_id() => Workflow.process()}
        ) :: :ok
  def register_workflow(workflow_id, channels, processes) do
    GenServer.call(via_name(workflow_id), {:register_workflow, channels, processes})
  end

  @doc "Return all subscriptions as `channel_id => [process_id]`."
  @spec get_subscriptions(Workflow.id()) ::
          %{Workflow.channel_id() => [Workflow.process_id()]}
  def get_subscriptions(workflow_id) do
    case :ets.lookup(@table, workflow_id) do
      [{^workflow_id, data}] -> data.subscriptions
      [] -> %{}
    end
  end

  @doc "Fetch a single process definition by id, or `nil` if not registered."
  @spec get_process(Workflow.id(), Workflow.process_id()) :: Workflow.process() | nil
  def get_process(workflow_id, process_id) do
    case :ets.lookup(@table, workflow_id) do
      [{^workflow_id, data}] -> Map.get(data.processes, process_id)
      [] -> nil
    end
  end

  @doc """
  Fetch a single process definition by name within a workflow, or `nil` if not found.
  """
  @spec get_process_by_name(Workflow.id(), String.t()) :: Workflow.process() | nil
  def get_process_by_name(workflow_id, name) do
    case :ets.lookup(@table, workflow_id) do
      [{^workflow_id, data}] ->
        case Map.get(data.names_index, name) do
          nil -> nil
          process_id -> Map.get(data.processes, process_id)
        end

      [] ->
        nil
    end
  end

  @doc "Fetch all registered channel metadata."
  @spec get_channels(Workflow.id()) :: %{Workflow.channel_id() => channel_meta()}
  def get_channels(workflow_id) do
    case :ets.lookup(@table, workflow_id) do
      [{^workflow_id, data}] -> data.channels
      [] -> %{}
    end
  end

  @impl true
  @spec init(keyword()) :: {:ok, server_state()}
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    # Trap exits so we can clean up the ETS table when the workflow terminates
    Process.flag(:trap_exit, true)

    {:ok, %{workflow_id: workflow_id}}
  end

  @impl true
  def handle_call({:register_workflow, channels, processes}, _from, state) do
    subscriptions = derive_subscriptions(processes)
    names_index = Map.new(processes, fn {id, p} -> {p.name, id} end)

    data = %Athanor.Workflow.Registry.WorkflowData{
      channels: channels,
      processes: processes,
      subscriptions: subscriptions,
      names_index: names_index
    }

    :ets.insert(@table, {state.workflow_id, data})

    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    :ets.delete(@table, state.workflow_id)
  end

  defp derive_subscriptions(processes) do
    Enum.reduce(processes, %{}, fn {process_id, process}, acc ->
      Enum.reduce(process.input, acc, fn {_name, input_def}, subs ->
        Map.update(subs, input_def.channel_id, [process_id], &[process_id | &1])
      end)
    end)
  end
end
