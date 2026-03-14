defmodule Athanor.Domain.Channel do
  @moduledoc """
  An append-only stream of ArtifactRefs.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Athanor.Domain.ArtifactRef

  @primary_key false
  embedded_schema do
    field(:id, :string)
    # The process ID that publishes to this channel
    field(:producer_id, :string)
    # The append-only list
    embeds_many(:items, ArtifactRef)
    # Set to true when the producer finishes
    field(:closed?, :boolean, default: false)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          producer_id: String.t() | nil,
          items: [ArtifactRef.t()],
          closed?: boolean()
        }

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:id, :producer_id, :closed?])
    |> cast_embed(:items)
    |> validate_required([:id])
  end

  @doc """
  Appends an ArtifactRef to the channel items.
  """
  def append_item(%__MODULE__{closed?: true} = channel, _item), do: channel

  def append_item(%__MODULE__{items: items} = channel, %ArtifactRef{} = item) do
    %{channel | items: items ++ [item]}
  end

  @doc """
  Marks the channel as closed for new items.
  """
  def close(%__MODULE__{} = channel) do
    %{channel | closed?: true}
  end

  @doc """
  Returns true if the channel has no items.
  """
  def empty?(%__MODULE__{items: []}), do: true
  def empty?(%__MODULE__{}), do: false
end
