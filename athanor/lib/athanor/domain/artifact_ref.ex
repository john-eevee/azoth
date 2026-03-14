defmodule Athanor.Domain.ArtifactRef do
  @moduledoc """
  A content-addressed reference to a data artifact.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:uri, :string)
    field(:digest, :string)
    field(:metadata, :map, default: %{})
  end

  @type t :: %__MODULE__{
          uri: String.t(),
          digest: String.t() | nil,
          metadata: map() | nil
        }

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:uri, :digest, :metadata])
    |> validate_required([:uri])
  end

  @doc """
  Returns a string stem of the filename (useful for path templates).
  """
  def stem(%__MODULE__{uri: uri}) do
    uri |> Path.basename() |> String.split(".") |> List.first()
  end
end
