defmodule Athanor.Workflow do
  @moduledoc """
  The top-level container for a distributed reactive workflow.
  """

  @enforce_keys [:name]
  defstruct [:name, processes: [], channels: []]

  @type t :: %__MODULE__{
          name: String.t(),
          processes: [Athanor.Process.t()],
          channels: [Athanor.Channel.t()]
        }
end
