defmodule Athanor.Domain.Workflow do
  @moduledoc """
  The top-level container for a distributed reactive workflow.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Athanor.Domain.{Process, Channel, Subscription}

  @primary_key false
  embedded_schema do
    field(:name, :string)
    embeds_many(:processes, Process)
    embeds_many(:channels, Channel)
    embeds_many(:subscriptions, Subscription)
  end

  @type t :: %__MODULE__{
          name: String.t(),
          processes: [Process.t()],
          channels: [Channel.t()],
          subscriptions: [Subscription.t()]
        }

  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name])
    |> cast_embed(:processes)
    |> cast_embed(:channels)
    |> cast_embed(:subscriptions)
    |> validate_required([:name])
  end
end
