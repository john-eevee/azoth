defmodule Athanor.DSL.RetryTest do
  use ExUnit.Case, async: true
  alias Athanor.DSL.Parser

  test "parses exponential retry" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            outputs {
                "*"
            }
            resources cpu=1 mem=1.0 disk=1.0
            retry backoff="exponential" count=5 exponent=2.5 initial_delay=1000
        }
    }
    """

    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, &(&1.name == "retry_step"))

    assert proc.retry == %{
             backoff: "exponential",
             count: 5,
             exponent: 2.5,
             initial_delay: 1000
           }
  end

  test "parses exponential retry with default initial_delay" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            outputs {
                "*"
            }
            resources cpu=1 mem=1.0 disk=1.0
            retry backoff="exponential" count=3 exponent=2.0
        }
    }
    """

    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, &(&1.name == "retry_step"))
    assert proc.retry.initial_delay == 500
  end

  test "parses linear retry with padding" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            outputs {
                "*"
            }
            resources cpu=1 mem=1.0 disk=1.0
            retry backoff="linear" count=4 delays="1000, 2000"
        }
    }
    """

    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, &(&1.name == "retry_step"))

    assert proc.retry == %{
             backoff: "linear",
             count: 4,
             delays: [1000, 2000, 2000, 2000]
           }
  end

  test "parses linear retry with truncation" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            outputs {
                "*"
            }
            resources cpu=1 mem=1.0 disk=1.0
            retry backoff="linear" count=2 delays="1000, 2000, 3000"
        }
    }
    """

    {:ok, plan} = Parser.parse(src)
    proc = Enum.find(plan.processes, &(&1.name == "retry_step"))
    assert proc.retry.delays == [1000, 2000]
  end

  test "returns error for invalid backoff strategy" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            retry backoff="magic" count=2
        }
    }
    """

    assert {:error, msg} = Parser.parse(src)
    assert msg =~ "invalid retry backoff strategy" or msg =~ "magic"
  end

  test "returns error when retry is missing properties" do
    src = """
    workflow "retry_test" {
        process "retry_step" {
            image "img:1"
            command "run"
            retry "random_value"
        }
    }
    """

    assert {:error, msg} = Parser.parse(src)
    assert msg =~ "invalid retry" or msg =~ "must be a dict" or msg =~ "retry must be"
  end
end
