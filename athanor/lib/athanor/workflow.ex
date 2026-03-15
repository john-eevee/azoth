defmodule Athanor.Workflow do
  @type id() :: Uniq.UUID

  @type indexed(t) :: %{non_neg_integer() => t}

  @type cursor() :: non_neg_integer()

  @type artifact() :: %{
          uri: URI.t(),
          hash: nonempty_binary(),
          metadata: map()
        }

  @type channel() :: %{
          producer_id: id(),
          items: indexed(artifact()),
          closed?: boolean()
        }

  @type channel_id() :: id()

  @type process_id() :: id()

  @type subscription() :: %{cursor: cursor(), process_id: process_id()}

  @type process() :: %{
          image: String.t(),
          command: String.t(),
          input: %{String.t() => String.t()},
          resources: %{
            mem: non_neg_integer() | :inf,
            cpu: float() | :inf,
            disk: non_neg_integer() | :inf
          }
        }
end
