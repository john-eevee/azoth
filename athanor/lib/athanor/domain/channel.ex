defmodule Athanor.Channel do
  @moduledoc """
  An append-only stream of ArtifactRefs.
  """

  @type status :: :active | :closed

  @enforce_keys [:id, :type]
  defstruct [:id, :type, status: :active, items: []]

  @type t :: %__MODULE__{
          id: String.t(),
          type: :path | :result | :literal,
          status: status(),
          items: [Athanor.ArtifactRef.t()]
        }
end
