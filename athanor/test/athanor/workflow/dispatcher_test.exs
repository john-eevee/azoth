defmodule Athanor.Workflow.DispatcherTest do
  use ExUnit.Case, async: true

  alias Athanor.Workflow.Dispatcher

  defp unique_id, do: Uniq.UUID.uuid7()

  defp artifact(uri) do
    %{uri: URI.parse(uri), hash: "abc123", metadata: %{}}
  end

  defp process do
    %{
      image: "genomics/bwa:0.7.17",
      command: "bwa mem -t 8 {ref} {reads}",
      input: %{},
      output_search_patterns: ["./output/*.bam"],
      resources: %{cpu: 8.0, mem: 16_384, disk: 51_200},
      retry: %{backoff: :exponential, count: 3, exponent: 2.0, initial_delay: 500}
    }
  end

  setup do
    # Use the stub dispatcher for all tests in this module
    Application.put_env(:athanor, :dispatcher_impl, Athanor.Workflow.Dispatcher.StubDispatcher)
    :ok
  end

  describe "build_voucher/3" do
    test "maps task and process fields to the voucher shape" do
      wid = unique_id()
      fingerprint = "deadbeef"

      task = %{
        process_id: unique_id(),
        status: :pending,
        fingerprint: fingerprint,
        input_artifacts: [artifact("s3://bucket/reads.fq.gz")],
        output_artifacts: []
      }

      voucher = Dispatcher.build_voucher(wid, task, process())

      assert voucher.workflow_id == wid
      assert voucher.fingerprint == fingerprint
      assert voucher.image == "genomics/bwa:0.7.17"
      assert voucher.command == "bwa mem -t 8 {ref} {reads}"
      assert voucher.output_search_patterns == ["./output/*.bam"]
      assert voucher.resources.cpu == 8.0

      assert voucher.retry == %{
               backoff: :exponential,
               count: 3,
               exponent: 2.0,
               initial_delay: 500
             }

      assert length(voucher.inputs) == 1
      [input] = voucher.inputs
      assert input.uri == "s3://bucket/reads.fq.gz"
    end
  end

  describe "StubDispatcher.dispatch/1" do
    test "returns {:ok, fingerprint}" do
      wid = unique_id()
      fingerprint = "cafebabe"

      task = %{
        process_id: unique_id(),
        status: :pending,
        fingerprint: fingerprint,
        input_artifacts: [artifact("s3://bucket/sample.fq.gz")],
        output_artifacts: []
      }

      voucher = Dispatcher.build_voucher(wid, task, process())

      assert {:ok, ^fingerprint} = Dispatcher.dispatch(voucher)
    end
  end
end
