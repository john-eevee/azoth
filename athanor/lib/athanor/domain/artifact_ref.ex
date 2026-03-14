defmodule Athanor.Domain.ArtifactRef do
  @moduledoc """
  A content-addressed reference to a data artifact.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:uri, :string)
    field(:digest, :string)
    field(:metadata, :map)
  end

  @type t :: %__MODULE__{
          uri: String.t(),
          digest: String.t() | nil,
          metadata: map() | nil
        }
end
