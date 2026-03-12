defmodule Athanor.Workflow do
  use Ecto.Schema

  alias Athanor.Channel
  alias Athanor.Process
  alias Ecto.Changeset

  embedded_schema do
    field :name, :string
    embeds_many :processes, Process
    embeds_many :channels, Channel
  end
end
