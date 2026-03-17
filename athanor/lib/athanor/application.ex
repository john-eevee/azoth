defmodule Athanor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # One DynamicSupervisor that owns all per-workflow Instance subtrees.
      # Start a new workflow via:
      #   DynamicSupervisor.start_child(Athanor.Workflow.Supervisor,
      #     {Athanor.Workflow.Instance, workflow_id: id})
      {DynamicSupervisor, name: Athanor.Workflow.Supervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Athanor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
