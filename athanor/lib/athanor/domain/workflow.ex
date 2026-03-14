defmodule Athanor.Domain.Workflow do
  @moduledoc """
  The top-level container for a distributed reactive workflow.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:name, :string)
    embeds_many(:processes, Athanor.Domain.Process)
    embeds_many(:channels, Athanor.Domain.Channel)
    embeds_many(:subscriptions, Athanor.Domain.Subscription)
  end

  @type t :: %__MODULE__{
          name: String.t(),
          processes: [Athanor.Domain.Process.t()],
          channels: [Athanor.Domain.Channel.t()],
          subscriptions: [Athanor.Domain.Subscription.t()]
        }
end
