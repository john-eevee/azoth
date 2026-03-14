defmodule Athanor.ArtifactRef do
  @moduledoc """
  A content-addressed reference to a data artifact.
  """

  @enforce_keys [:uri]
  defstruct [:uri, :digest, :metadata]

  @type t :: %__MODULE__{
          uri: String.t(),
          digest: String.t() | nil,
          metadata: map() | nil
        }
end
