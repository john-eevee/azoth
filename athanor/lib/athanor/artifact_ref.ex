defmodule Athanor.ArtifactRef do
  use Ecto.Schema

  embedded_schema do
    field :uri, :string
    field :checksum, :string
    field :size_kb, :integer
    field :pattern_match, :string
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(attrs, [:uri, :checksum, :size_kb, :pattern_match])
    |> Ecto.Changeset.validate_required([:uri, :checksum, :size_kb, :pattern_match])
  end
end
