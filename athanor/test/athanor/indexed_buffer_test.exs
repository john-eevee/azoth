defmodule Athanor.IndexedBufferTest do
  use ExUnit.Case, async: true
  doctest Athanor.IndexedBuffer

  alias Athanor.IndexedBuffer

  # ---------------------------------------------------------------------------
  # new/0
  # ---------------------------------------------------------------------------

  describe "new/0" do
    test "returns an empty buffer" do
      buf = IndexedBuffer.new()
      assert buf.count == 0
      assert buf.items == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # append/2 — single item
  # ---------------------------------------------------------------------------

  describe "append/2 with a single item" do
    test "assigns index 0 to the first item" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append(:a)
      assert buf.count == 1
      assert IndexedBuffer.at(buf, 0) == :a
    end

    test "assigns consecutive indices on repeated appends" do
      buf =
        IndexedBuffer.new()
        |> IndexedBuffer.append(:a)
        |> IndexedBuffer.append(:b)
        |> IndexedBuffer.append(:c)

      assert IndexedBuffer.at(buf, 0) == :a
      assert IndexedBuffer.at(buf, 1) == :b
      assert IndexedBuffer.at(buf, 2) == :c
      assert buf.count == 3
    end

    test "accepts any non-nil term (integer, string, map, tuple)" do
      buf =
        IndexedBuffer.new()
        |> IndexedBuffer.append(42)
        |> IndexedBuffer.append("hello")
        |> IndexedBuffer.append(%{key: :value})
        |> IndexedBuffer.append({:ok, 1})

      assert IndexedBuffer.at(buf, 0) == 42
      assert IndexedBuffer.at(buf, 1) == "hello"
      assert IndexedBuffer.at(buf, 2) == %{key: :value}
      assert IndexedBuffer.at(buf, 3) == {:ok, 1}
    end

    test "raises ArgumentError when item is nil" do
      assert_raise ArgumentError, ~r/nil items are not allowed/, fn ->
        IndexedBuffer.new() |> IndexedBuffer.append(nil)
      end
    end

    test "does not mutate the original buffer" do
      original = IndexedBuffer.new() |> IndexedBuffer.append(:a)
      _new = IndexedBuffer.append(original, :b)
      assert original.count == 1
    end
  end

  # ---------------------------------------------------------------------------
  # append/2 — list of items
  # ---------------------------------------------------------------------------

  describe "append/2 with a list" do
    test "appends all items in order" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([1, 2, 3])
      assert buf.count == 3
      assert IndexedBuffer.at(buf, 0) == 1
      assert IndexedBuffer.at(buf, 1) == 2
      assert IndexedBuffer.at(buf, 2) == 3
    end

    test "appending an empty list is a no-op" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append(:a) |> IndexedBuffer.append([])
      assert buf.count == 1
    end

    test "continues existing indices when appending a second list" do
      buf =
        IndexedBuffer.new()
        |> IndexedBuffer.append([:a, :b])
        |> IndexedBuffer.append([:c, :d])

      assert IndexedBuffer.at(buf, 0) == :a
      assert IndexedBuffer.at(buf, 2) == :c
      assert IndexedBuffer.at(buf, 3) == :d
      assert buf.count == 4
    end

    test "raises ArgumentError when list contains nil" do
      assert_raise ArgumentError, ~r/nil items are not allowed/, fn ->
        IndexedBuffer.new() |> IndexedBuffer.append([1, nil, 3])
      end
    end

    test "does not partially append when list contains nil" do
      buf = IndexedBuffer.new()

      assert_raise ArgumentError, fn ->
        IndexedBuffer.append(buf, [1, nil, 3])
      end

      # original buf is unchanged (count still 0)
      assert buf.count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # at/2
  # ---------------------------------------------------------------------------

  describe "at/2" do
    setup do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:a, :b, :c])
      %{buf: buf}
    end

    test "returns item at valid index", %{buf: buf} do
      assert IndexedBuffer.at(buf, 0) == :a
      assert IndexedBuffer.at(buf, 1) == :b
      assert IndexedBuffer.at(buf, 2) == :c
    end

    test "returns nil for out-of-bounds index", %{buf: buf} do
      assert IndexedBuffer.at(buf, 3) == nil
      assert IndexedBuffer.at(buf, 100) == nil
    end

    test "returns nil for index 0 on empty buffer" do
      assert IndexedBuffer.at(IndexedBuffer.new(), 0) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # from_cursor/2
  # ---------------------------------------------------------------------------

  describe "from_cursor/2" do
    setup do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:a, :b, :c, :d])
      %{buf: buf}
    end

    test "returns all items when cursor is 0", %{buf: buf} do
      assert IndexedBuffer.from_cursor(buf, 0) == [:a, :b, :c, :d]
    end

    test "returns tail from given cursor", %{buf: buf} do
      assert IndexedBuffer.from_cursor(buf, 2) == [:c, :d]
    end

    test "returns the last item when cursor is count - 1", %{buf: buf} do
      assert IndexedBuffer.from_cursor(buf, 3) == [:d]
    end

    test "returns empty list when cursor equals count (fully caught up)", %{buf: buf} do
      assert IndexedBuffer.from_cursor(buf, 4) == []
    end

    test "returns empty list for an empty buffer at cursor 0" do
      buf = IndexedBuffer.new()
      assert IndexedBuffer.from_cursor(buf, 0) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Enumerable — Enum integration
  # ---------------------------------------------------------------------------

  describe "Enumerable" do
    setup do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:x, :y, :z])
      %{buf: buf}
    end

    test "Enum.to_list/1 returns items in insertion order", %{buf: buf} do
      assert Enum.to_list(buf) == [:x, :y, :z]
    end

    test "Enum.count/1 returns the number of items", %{buf: buf} do
      assert Enum.count(buf) == 3
    end

    test "Enum.count/1 returns 0 for empty buffer" do
      assert Enum.count(IndexedBuffer.new()) == 0
    end

    test "Enum.member?/2 returns true for present item", %{buf: buf} do
      assert Enum.member?(buf, :y)
    end

    test "Enum.member?/2 returns false for absent item", %{buf: buf} do
      refute Enum.member?(buf, :not_present)
    end

    test "Enum.map/2 transforms each item in order", %{buf: buf} do
      result = Enum.map(buf, &inspect/1)
      assert result == [":x", ":y", ":z"]
    end

    test "Enum.filter/2 filters items", %{buf: buf} do
      result = Enum.filter(buf, fn x -> x != :y end)
      assert result == [:x, :z]
    end

    test "Enum.reduce/3 folds items in insertion order", %{buf: buf} do
      result = Enum.reduce(buf, [], fn item, acc -> [item | acc] end)
      # reduce builds a reversed list — check order is insertion order
      assert result == [:z, :y, :x]
    end

    test "Enum.take/2 returns the first N items", %{buf: buf} do
      assert Enum.take(buf, 2) == [:x, :y]
    end

    test "Enum.slice/2 returns a subsequence by range" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([0, 1, 2, 3, 4])
      assert Enum.slice(buf, 1..3) == [1, 2, 3]
    end

    test "Enum.at/2 returns element by index via Enumerable" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:a, :b, :c])
      assert Enum.at(buf, 1) == :b
    end

    test "empty buffer enumerates to empty list" do
      assert Enum.to_list(IndexedBuffer.new()) == []
    end

    test "works with Stream.map/2" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([1, 2, 3])
      result = buf |> Stream.map(&(&1 * 2)) |> Enum.to_list()
      assert result == [2, 4, 6]
    end
  end

  # ---------------------------------------------------------------------------
  # stream_from_cursor/2
  # ---------------------------------------------------------------------------

  describe "stream_from_cursor/2" do
    setup do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:a, :b, :c, :d])
      %{buf: buf}
    end

    test "returns a Stream (lazy, not a list)", %{buf: buf} do
      result = IndexedBuffer.stream_from_cursor(buf, 0)
      assert is_struct(result, Stream) or is_function(result) or match?(%Stream{}, result)
      # Must NOT be a plain list
      refute is_list(result)
    end

    test "cursor 0 yields all items in order", %{buf: buf} do
      assert buf |> IndexedBuffer.stream_from_cursor(0) |> Enum.to_list() == [:a, :b, :c, :d]
    end

    test "cursor in the middle yields tail", %{buf: buf} do
      assert buf |> IndexedBuffer.stream_from_cursor(2) |> Enum.to_list() == [:c, :d]
    end

    test "cursor at last index yields single item", %{buf: buf} do
      assert buf |> IndexedBuffer.stream_from_cursor(3) |> Enum.to_list() == [:d]
    end

    test "cursor equal to count yields empty stream", %{buf: buf} do
      assert buf |> IndexedBuffer.stream_from_cursor(4) |> Enum.to_list() == []
    end

    test "empty buffer with cursor 0 yields empty stream" do
      buf = IndexedBuffer.new()
      assert buf |> IndexedBuffer.stream_from_cursor(0) |> Enum.to_list() == []
    end

    test "is lazy — only evaluates items that are consumed", %{buf: buf} do
      # Stream.take forces only the first 2 items without walking the rest
      result = buf |> IndexedBuffer.stream_from_cursor(0) |> Stream.take(2) |> Enum.to_list()
      assert result == [:a, :b]
    end

    test "composes with other Stream operations", %{buf: buf} do
      result =
        buf
        |> IndexedBuffer.stream_from_cursor(1)
        |> Stream.map(&inspect/1)
        |> Stream.reject(&(&1 == ":c"))
        |> Enum.to_list()

      assert result == [":b", ":d"]
    end

    test "snapshot semantics — items appended after call are not included" do
      buf = IndexedBuffer.new() |> IndexedBuffer.append([:a, :b])
      stream = IndexedBuffer.stream_from_cursor(buf, 0)
      # Append to a new version of the buffer (structs are immutable)
      _buf2 = IndexedBuffer.append(buf, :c)
      # The stream was created from the original snapshot — :c is not visible
      assert Enum.to_list(stream) == [:a, :b]
    end

    test "raises FunctionClauseError for negative cursor", %{buf: buf} do
      assert_raise FunctionClauseError, fn ->
        IndexedBuffer.stream_from_cursor(buf, -1)
      end
    end

    test "raises FunctionClauseError for cursor beyond count", %{buf: buf} do
      assert_raise FunctionClauseError, fn ->
        IndexedBuffer.stream_from_cursor(buf, 99)
      end
    end
  end
end
