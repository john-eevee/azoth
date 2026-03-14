defmodule Athanor.Domain.Subscription do
  @moduledoc """
  A subscription by a process to a specific channel's item stream.
  """
  use Ecto.Schema
  import Ecto.Changeset

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

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:channel_id, :process_id, :cursor])
    |> validate_required([:channel_id, :process_id])
    |> validate_number(:cursor, greater_than_or_equal_to: 0)
  end

  @doc """
  Increments the cursor, typically after a TaskRun is successfully scheduled.
  """
  def advance_cursor(%__MODULE__{cursor: cursor} = subscription) do
    %{subscription | cursor: cursor + 1}
  end

  @doc """
  Resets the cursor to the beginning (useful for re-runs).
  """
  def reset_cursor(%__MODULE__{} = subscription) do
    %{subscription | cursor: 0}
  end
end
