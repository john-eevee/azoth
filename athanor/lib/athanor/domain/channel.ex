defmodule Athanor.Domain.Channel do
  @moduledoc """
  An append-only stream of ArtifactRefs.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:id, :string)
    # The process ID that publishes to this channel
    field(:producer_id, :string)
    # The append-only list
    embeds_many(:items, Athanor.Domain.ArtifactRef)
    # Set to true when the producer finishes
    field(:closed?, :boolean, default: false)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          producer_id: String.t() | nil,
          items: [Athanor.Domain.ArtifactRef.t()],
          closed?: boolean()
        }
end
