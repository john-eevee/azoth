defmodule Athanor.DSL.ValidatorTest do
  @moduledoc """
  Integration tests for schema validation, placeholder validation, and URI scheme validation.

  All validation errors should be collected and returned together, not just the first one.
  """

  use ExUnit.Case, async: true

  alias Athanor.DSL.Parser

  @fixtures Path.join([__DIR__, "../../fixtures/dsl"])

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  # ---------------------------------------------------------------------------
  # Valid workflows — should parse without errors
  # ---------------------------------------------------------------------------

  test "genomics_pipeline.kdl validates without errors" do
    {:ok, _plan} = Parser.parse(fixture("genomics_pipeline.kdl"))
  end

  test "dynamic_split_align.kdl validates without errors" do
    {:ok, _plan} = Parser.parse(fixture("dynamic_split_align.kdl"))
  end

  # ---------------------------------------------------------------------------
  # Placeholder validation tests
  # ---------------------------------------------------------------------------

  test "unresolvable placeholder in command raises error" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} {unknown_key}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} {unknown_key}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "unknown_key")
    assert String.contains?(msg, "cannot be resolved")
  end

  test "valid resource placeholder {cpu} in command" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process -c {cpu} {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=4 mem=8.0 disk=20.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process -c {cpu} {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=4 mem=8.0 disk=20.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "all resource placeholders {cpu}, {mem}, {disk} are valid" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "program -c {cpu} -m {mem} -d {disk} {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=4 mem=8.0 disk=20.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "program -c {cpu} -m {mem} -d {disk} {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=4 mem=8.0 disk=20.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "output key placeholder {result} in command is valid" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  # ---------------------------------------------------------------------------
  # URI scheme validation tests
  # ---------------------------------------------------------------------------

  test "invalid URI scheme (http://) raises error" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "http://bucket/out.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "http://bucket/out.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "unsupported URI scheme")
    assert String.contains?(msg, "http")
  end

  test "valid s3:// URI scheme" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://my-bucket/output/file.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://my-bucket/output/file.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "valid gs:// URI scheme" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "gs://gcs-bucket/output/file.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "gs://gcs-bucket/output/file.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "valid nfs:// URI scheme" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "nfs://server/path/file.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "nfs://server/path/file.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "valid relative path (.) in output" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "./output/file.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "./output/file.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "valid absolute path (/) in output" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} -o {result}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "/data/output/file.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} -o {result}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "/data/output/file.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  # ---------------------------------------------------------------------------
  # Resource validation tests
  # ---------------------------------------------------------------------------

  test "negative CPU resource raises error" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=-1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=-1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "resource 'cpu' must be > 0")
  end

  test "zero memory resource raises error" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=1 mem=0.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=1 mem=0.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "resource 'mem' must be > 0")
  end

  test "negative disk resource raises error" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=1 mem=2.0 disk=-5.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=1 mem=2.0 disk=-5.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "resource 'disk' must be > 0")
  end

  test "positive float resources are valid" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "s3://bucket/out.txt"
        }
        resources cpu=0.5 mem=2.5 disk=10.5
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "s3://bucket/out.txt"
    }
    resources cpu=0.5 mem=2.5 disk=10.5
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  # ---------------------------------------------------------------------------
  # Multiple validation errors in one workflow
  # ---------------------------------------------------------------------------

  test "multiple validation errors are collected" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input} {unknown1} {unknown2}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "result" "http://bad-scheme/out.txt"
        }
        resources cpu=-1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input} {unknown1} {unknown2}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "result" "http://bad-scheme/out.txt"
    }
    resources cpu=-1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    # All errors should be present in the message
    assert String.contains?(msg, "unknown1")
    assert String.contains?(msg, "unknown2")
    assert String.contains?(msg, "unsupported URI scheme")
    assert String.contains?(msg, "resource 'cpu' must be > 0")
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "output URI can use property notation like {data.stem}" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {data}"
        inputs {
            "data" "data_channel"
        }
        outputs {
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {data}"
    inputs {
        "data" "data_channel"
    }
    outputs {
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "glob outputs do not require URI scheme validation" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "split_tool {data}"
        inputs {
            "data" "data_channel"
        }
        outputs {
            "./chunks/*.fa"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "split_tool {data}"
    inputs {
        "data" "data_channel"
    }
    outputs {
        "./chunks/*.fa"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "multiple output keys with mixed valid schemes" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "s3_out" "s3://bucket/out1.txt"
            "gs_out" "gs://bucket/out2.txt"
            "local_out" "./output.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "s3_out" "s3://bucket/out1.txt"
        "gs_out" "gs://bucket/out2.txt"
        "local_out" "./output.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:ok, _plan} = Parser.parse(src)
  end

  test "invalid output scheme in one of multiple outputs" do
    src = """
<<<<<<< HEAD
    workflow "test" {
        channel "data_channel" type="literal" "s3://bucket/input.txt"

        process "test_proc" {
        image "test:latest"
        command "process {input}"
        inputs {
            "input" "data_channel"
        }
        outputs {
            "good" "s3://bucket/out1.txt"
            "bad" "ftp://server/out2.txt"
        }
        resources cpu=1 mem=2.0 disk=10.0
        }
    }
=======
    channel "data_channel" type="literal" "s3://bucket/input.txt"

    process "test_proc" {
    image "test:latest"
    command "process {input}"
    inputs {
        "input" "data_channel"
    }
    outputs {
        "good" "s3://bucket/out1.txt"
        "bad" "ftp://server/out2.txt"
    }
    resources cpu=1 mem=2.0 disk=10.0
    }

    workflow "test" {}
>>>>>>> 09da343 (feat: migrate from Starlark DSL to KDL parser)
    """

    {:error, msg} = Parser.parse(src)
    assert String.contains?(msg, "ftp")
    assert String.contains?(msg, "unsupported URI scheme")
  end
end
