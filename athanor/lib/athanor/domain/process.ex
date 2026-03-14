defmodule Athanor.Domain.Process do
  @moduledoc """
  A unit of work that executes a command inside a container image.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:id, :string)
    field(:image, :string)
    field(:command, :string)
    # URI templates or channel references as strings/maps
    field(:inputs, :map, default: %{})
    # Named URI templates or list of globs
    field(:outputs, {:array, :string}, default: [])
    field(:resources, :map, default: %{})
  end

  @type t :: %__MODULE__{
          id: String.t(),
          image: String.t(),
          command: String.t(),
          inputs: map(),
          outputs: [String.t()],
          resources: map()
        }

  def changeset(process, attrs) do
    process
    |> cast(attrs, [:id, :image, :command, :inputs, :outputs, :resources])
    |> validate_required([:id, :image, :command])
  end
end
