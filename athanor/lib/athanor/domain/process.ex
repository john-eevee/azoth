defmodule Athanor.Process do
  @moduledoc """
  A unit of work that executes a command inside a container image.
  """

  @enforce_keys [:id, :image, :command]
  defstruct [:id, :image, :command, inputs: %{}, outputs: %{}, resources: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          image: String.t(),
          command: String.t(),
          inputs: %{String.t() => String.t() | Athanor.Channel.t()},
          outputs: %{String.t() => String.t()} | [String.t()],
          resources: %{String.t() => number() | String.t()}
        }
end
