defmodule Athanor.DSL.RetryTest do
  use ExUnit.Case, async: true
  alias Athanor.DSL.Parser

  test "parses exponential retry" do
    src = """
    def main():
        process(
            name = "retry_step",
            image = "img:1",
            command = "run",
            inputs = {},
            outputs = ["*"],
            resources = {"cpu": 1, "mem": 1, "disk": 1},
            retry = {"backoff": "exponential", "count": 5, "exponent": 2.5, "initial_delay": 1000}
        )
        workflow(name = "retry_test")
    """
    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, & &1.name == "retry_step")
    assert proc.retry == %{
      backoff: :exponential,
      count: 5,
      exponent: 2.5,
      initial_delay: 1000
    }
  end

  test "parses exponential retry with default initial_delay" do
    src = """
    def main():
        process(
            name = "retry_step",
            image = "img:1",
            command = "run",
            inputs = {},
            outputs = ["*"],
            resources = {"cpu": 1, "mem": 1, "disk": 1},
            retry = {"backoff": "exponential", "count": 3, "exponent": 2.0}
        )
        workflow(name = "retry_test")
    """
    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, & &1.name == "retry_step")
    assert proc.retry.initial_delay == 500
  end

  test "parses linear retry with padding" do
    src = """
    def main():
        process(
            name = "retry_step",
            image = "img:1",
            command = "run",
            inputs = {},
            outputs = ["*"],
            resources = {"cpu": 1, "mem": 1, "disk": 1},
            retry = {"backoff": "linear", "count": 4, "delays": [1000, 2000]}
        )
        workflow(name = "retry_test")
    """
    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, & &1.name == "retry_step")
    assert proc.retry == %{
      backoff: :linear,
      count: 4,
      delays: [1000, 2000, 2000, 2000]
    }
  end

  test "parses linear retry with truncation" do
    src = """
    def main():
        process(
            name = "retry_step",
            image = "img:1",
            command = "run",
            inputs = {},
            outputs = ["*"],
            resources = {"cpu": 1, "mem": 1, "disk": 1},
            retry = {"backoff": "linear", "count": 2, "delays": [1000, 2000, 3000]}
        )
        workflow(name = "retry_test")
    """
    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, & &1.name == "retry_step")
    assert proc.retry.delays == [1000, 2000]
  end

  test "returns error for invalid backoff strategy" do
    src = """
    def main():
        process(
            name = "retry_step",
            image = "img:1",
            command = "run",
            inputs = {},
            outputs = ["*"],
            resources = {"cpu": 1, "mem": 1, "disk": 1},
            retry = {"backoff": "invalid", "count": 1}
        )
        workflow(name = "retry_test")
    """
    assert {:error, reason} = Parser.parse(src)
    assert reason =~ "invalid retry backoff 'invalid'"
  end
end
