defmodule Athanor.Domain.ArtifactRef do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :uri, :string
    field :checksum, :string
    field :size_kb, :integer
    field :pattern_match, :string
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, fields())
    |> validate_required(required_fields())
  end

  defp fields() do
    ~w(uri checksum size_kb pattern_match)a
  end

  defp required_fields() do
    fields()
  end
end

defmodule Athanor.Domain.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, Ecto.UUID
    # the process id that publishes into this channel
    field :producer_id, Ecto.UUID
    # if the producer finished inserting into this channel
    field :closed?, :boolean, default: false
    # append-only list
    embeds_many :items, Athanor.Domain.ArtifactRef
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, fields())
    |> validate_required(required_fields())
    |> cast_embed(:items, with: &Athanor.Domain.ArtifactRef.changeset/1)
  end

  defp fields do
    ~w(id producer_id closed?)a
  end

  defp required_fields do
    ~w(id producer_id)a
  end
end
