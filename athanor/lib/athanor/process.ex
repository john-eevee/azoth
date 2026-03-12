defmodule Athanor.Process do
  use Ecto.Schema

  alias Athanor.ArtifactRef

  embedded_schema do
    field :image, :string
    field :command, :string
    field :cpu_resource, :float
    field :mem_resource, :float
    field :disk_resource, :float
    embeds_many :inputs, ArtifactRef
    embeds_many :outputs, ArtifactRef
  end
end
