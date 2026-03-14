defmodule Athanor.Domain.TaskRun do
  @moduledoc """
  A single execution instance of a Process, triggered by an item from its input channel.
  """
  use Ecto.Schema

  schema "task_runs" do
    field(:process_id, :string)
    # :pending, :running, :success, :failed
    field(:status, :string)
    field(:fingerprint, :string)

    # The EXACT artifacts handed to this run from the channel at the cursor position
    embeds_many(:consumed_inputs, Athanor.Domain.ArtifactRef)

    # The new artifacts Quicksilver discovered and published back
    embeds_many(:produced_outputs, Athanor.Domain.ArtifactRef)

    timestamps()
  end

  @type status :: :pending | :running | :success | :failed

  @type t :: %__MODULE__{
          process_id: String.t(),
          status: String.t(),
          fingerprint: String.t(),
          consumed_inputs: [Athanor.Domain.ArtifactRef.t()],
          produced_outputs: [Athanor.Domain.ArtifactRef.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
