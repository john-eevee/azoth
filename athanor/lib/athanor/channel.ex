defmodule Athanor.Channel do
  use Ecto.Schema

  alias Athanor.ArtifactRef

  embedded_schema do
    field :type, Ecto.Enum, values: [:path, :result, :literal]
    field :process_id, Ecto.UUID
    field :status, Ecto.Enum, values: [:pending, :active, :completed]
    field :options, :map
    embeds_many :artifacts, ArtifactRef
  end

  @doc "Fetch the head artifact from the channel (if any)."
  def hand_artifact(channel) do
    if Enum.empty?(channel.artifacts) do
      {:error, :empty}
    else
      {:ok, hd(channel.artifacts)}
    end
  end
end
