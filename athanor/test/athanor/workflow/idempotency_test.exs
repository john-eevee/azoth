defmodule Athanor.Workflow.IdempotencyTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Instance
  alias Athanor.Workflow.Supervisor, as: WorkflowSupervisor
  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  setup do
    Application.put_env(:athanor, :dispatcher_impl, Athanor.Workflow.Dispatcher.StubDispatcher)
    :ok
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  test "workflow submission is idempotent at the supervisor level" do
    wid = Uniq.UUID.uuid7()

    assert {:ok, pid1} =
             DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid})

    # Second start attempt for the same workflow ID should return already_started
    result = DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid})
    assert {:error, {:already_started, ^pid1}} = result
  end

  test "parsing same script yields identical workflow_id allowing idempotent submission" do
    script1 = fixture("genomics_pipeline.kdl")

    # Emulate submitting the workflow
    {:ok, %{plan: _plan1, fingerprint: hash1}} = Parser.parse_and_fingerprint(script1)
    wid1 = "wf_" <> String.slice(hash1, 0, 16)

    assert {:ok, pid1} =
             DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid1})

    # Later, submit exact same script (maybe some CI retries it)
    script2 = fixture("genomics_pipeline.kdl")
    {:ok, %{plan: _plan2, fingerprint: hash2}} = Parser.parse_and_fingerprint(script2)
    wid2 = "wf_" <> String.slice(hash2, 0, 16)

    assert wid1 == wid2

    result = DynamicSupervisor.start_child(WorkflowSupervisor, {Instance, workflow_id: wid2})
    assert {:error, {:already_started, ^pid1}} = result
  end

  test "parsing script with only cosmetic changes yields identical workflow_id" do
    script1 = fixture("genomics_pipeline.kdl")

    # Add comments and spacing
    script2 = """
    # This is a comment added at the top
    #{script1}

    # And some trailing whitespace
    """

    {:ok, %{fingerprint: hash1}} = Parser.parse_and_fingerprint(script1)
    {:ok, %{fingerprint: hash2}} = Parser.parse_and_fingerprint(script2)

    assert hash1 == hash2
  end
end
