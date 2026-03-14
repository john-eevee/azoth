defmodule Athanor.Domain.TaskRun do
  @moduledoc """
  A single execution instance of a Process, triggered by an item from its input channel.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Athanor.Domain.ArtifactRef

  schema "task_runs" do
    field(:process_id, :string)
    # :pending, :running, :success, :failed
    field(:status, :string, default: "pending")
    field(:fingerprint, :string)

    # The EXACT artifacts handed to this run from the channel at the cursor position
    embeds_many(:consumed_inputs, ArtifactRef)

    # The new artifacts Quicksilver discovered and published back
    embeds_many(:produced_outputs, ArtifactRef)

    timestamps()
  end

  @type status :: :pending | :running | :success | :failed

  @type t :: %__MODULE__{
          process_id: String.t(),
          status: String.t(),
          fingerprint: String.t(),
          consumed_inputs: [ArtifactRef.t()],
          produced_outputs: [ArtifactRef.t()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  def changeset(task_run, attrs) do
    task_run
    |> cast(attrs, [:process_id, :status, :fingerprint])
    |> cast_embed(:consumed_inputs)
    |> cast_embed(:produced_outputs)
    |> validate_required([:process_id, :status])
    |> validate_inclusion(:status, ["pending", "running", "success", "failed"])
  end

  @doc """
  Moves the task into the running state.
  """
  def start(%__MODULE__{} = task_run) do
    %{task_run | status: "running"}
  end

  @doc """
  Completes the task with discovered artifacts.
  """
  def succeed(%__MODULE__{} = task_run, artifacts \\ []) when is_list(artifacts) do
    %{task_run | status: "success", produced_outputs: artifacts}
  end

  @doc """
  Moves the task into the failed state.
  """
  def fail(%__MODULE__{} = task_run) do
    %{task_run | status: "failed"}
  end
end
