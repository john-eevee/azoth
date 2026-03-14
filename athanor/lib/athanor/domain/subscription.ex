defmodule Athanor.Domain.Subscription do
  @moduledoc """
  A subscription by a process to a specific channel's item stream.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:channel_id, :string)
    field(:process_id, :string)

    # The index of the next item in the channel's `items` array to be processed
    field(:cursor, :integer, default: 0)
  end

  @type t :: %__MODULE__{
          channel_id: String.t(),
          process_id: String.t(),
          cursor: integer()
        }
end
