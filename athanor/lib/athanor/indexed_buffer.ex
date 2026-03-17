defmodule Athanor.IndexedBuffer do
  @moduledoc """
  An append-only indexed buffer.

  Items are stored in insertion order and assigned a zero-based integer index.
  Once assigned, indices never change — existing items cannot be removed or
  overwritten.  This makes `IndexedBuffer` suitable as a persistent, ordered
  channel buffer where consumers can track their read position with a cursor.

  ## Features

  - `append/2` — add a single item or a list of items in one call
  - `at/2` — O(1) random access by index; returns `nil` for out-of-bounds
  - `from_cursor/2` — return all items from a given index onward (replay)
  - `stream_from_cursor/2` — lazy `Stream` version of `from_cursor/2`
  - `Enumerable` — works with the entire `Enum`/`Stream` family
  - Appending `nil` raises `ArgumentError`

  ## Examples

      iex> buf = Athanor.IndexedBuffer.new()
      iex> buf = Athanor.IndexedBuffer.append(buf, :a)
      iex> buf = Athanor.IndexedBuffer.append(buf, :b)
      iex> Athanor.IndexedBuffer.at(buf, 0)
      :a
      iex> Athanor.IndexedBuffer.at(buf, 1)
      :b
      iex> Athanor.IndexedBuffer.at(buf, 99)
      nil

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:x, :y, :z])
      iex> Enum.to_list(buf)
      [:x, :y, :z]
      iex> Enum.count(buf)
      3
      iex> Enum.member?(buf, :y)
      true

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c, :d])
      iex> Athanor.IndexedBuffer.from_cursor(buf, 2)
      [:c, :d]
      iex> Athanor.IndexedBuffer.from_cursor(buf, 4)
      []

  """

  @typedoc "An append-only buffer holding a count and a map of `index => item`."
  @type t() :: %__MODULE__{count: non_neg_integer(), items: %{non_neg_integer() => term()}}

  defstruct count: 0, items: %{}

  @doc """
  Creates an empty `IndexedBuffer`.

  ## Examples

      iex> Athanor.IndexedBuffer.new()
      %Athanor.IndexedBuffer{count: 0, items: %{}}

  """
  @spec new() :: t()
  def new(), do: %__MODULE__{count: 0, items: %{}}

  @doc """
  Appends one item or a list of items to the buffer.

  Items are assigned consecutive zero-based indices starting at the current
  buffer count.  The call is atomic for lists — either all items are appended
  or none are (if a `nil` is found, an `ArgumentError` is raised before any
  mutation occurs).

  ## Examples

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append(:hello)
      iex> Athanor.IndexedBuffer.at(buf, 0)
      :hello

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([1, 2, 3])
      iex> Enum.to_list(buf)
      [1, 2, 3]

      iex> Athanor.IndexedBuffer.append(Athanor.IndexedBuffer.new(), nil)
      ** (ArgumentError) nil items are not allowed in IndexedBuffer

      iex> Athanor.IndexedBuffer.append(Athanor.IndexedBuffer.new(), [1, nil, 3])
      ** (ArgumentError) nil items are not allowed in IndexedBuffer

  """
  @spec append(t(), list(term()) | term()) :: t()
  def append(this, items) when is_list(items) do
    if Enum.any?(items, &is_nil/1) do
      raise ArgumentError, "nil items are not allowed in IndexedBuffer"
    end

    Enum.reduce(items, this, fn item, %__MODULE__{count: count, items: acc_items} ->
      %__MODULE__{count: count + 1, items: Map.put(acc_items, count, item)}
    end)
  end

  def append(this, item) do
    if is_nil(item), do: raise(ArgumentError, "nil items are not allowed in IndexedBuffer")
    append(this, [item])
  end

  @doc """
  Returns the item at `index`, or `nil` if the index is out of bounds.

  ## Examples

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c])
      iex> Athanor.IndexedBuffer.at(buf, 0)
      :a
      iex> Athanor.IndexedBuffer.at(buf, 2)
      :c
      iex> Athanor.IndexedBuffer.at(buf, 100)
      nil

  """
  @spec at(t(), non_neg_integer()) :: term() | nil
  def at(%__MODULE__{items: items}, index) when is_integer(index) and index >= 0 do
    Map.get(items, index)
  end

  @doc """
  Returns all items from `cursor` (inclusive) to the end of the buffer.

  Use this to replay missed messages — pass the index of the first item you
  haven't seen yet.  When `cursor` equals the current count (i.e. you are
  fully caught up), an empty list is returned.

  Raises `FunctionClauseError` if `cursor` is negative or greater than the
  buffer count.

  ## Examples

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c])
      iex> Athanor.IndexedBuffer.from_cursor(buf, 0)
      [:a, :b, :c]
      iex> Athanor.IndexedBuffer.from_cursor(buf, 1)
      [:b, :c]
      iex> Athanor.IndexedBuffer.from_cursor(buf, 3)
      []

  """
  @spec from_cursor(t(), non_neg_integer()) :: list(term())
  def from_cursor(%__MODULE__{count: count, items: items}, cursor)
      when cursor >= 0 and cursor < count do
    Enum.map(cursor..(count - 1), &Map.fetch!(items, &1))
  end

  def from_cursor(%__MODULE__{count: count}, cursor) when cursor == count do
    []
  end

  @doc """
  Returns a lazy `Stream` of all items from `cursor` (inclusive) to the end
  of the buffer snapshot taken at call time.

  The buffer is snapshotted when `stream_from_cursor/2` is called; items
  appended to the buffer afterward are **not** included.  Use `from_cursor/2`
  if you need a plain list, or call `stream_from_cursor/2` again on the
  updated buffer to pick up new items.

  Raises `FunctionClauseError` if `cursor` is negative or greater than the
  buffer count at call time.

  ## Examples

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c, :d])
      iex> buf |> Athanor.IndexedBuffer.stream_from_cursor(1) |> Enum.to_list()
      [:b, :c, :d]

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c])
      iex> buf |> Athanor.IndexedBuffer.stream_from_cursor(3) |> Enum.to_list()
      []

      iex> buf = Athanor.IndexedBuffer.new() |> Athanor.IndexedBuffer.append([:a, :b, :c])
      iex> buf |> Athanor.IndexedBuffer.stream_from_cursor(0) |> Stream.map(&inspect/1) |> Enum.to_list()
      [":a", ":b", ":c"]

  """
  @spec stream_from_cursor(t(), non_neg_integer()) :: Enumerable.t()
  def stream_from_cursor(%__MODULE__{count: count, items: items}, cursor)
      when cursor >= 0 and cursor <= count do
    Stream.resource(
      fn -> cursor end,
      fn idx ->
        if idx >= count do
          {:halt, idx}
        else
          {[Map.fetch!(items, idx)], idx + 1}
        end
      end,
      fn _idx -> :ok end
    )
  end

  defimpl Enumerable do
    def count(this), do: {:ok, this.count}

    def slice(this) do
      {:ok, this.count,
       fn start, length, _step ->
         for i <- start..(start + length - 1), do: Map.get(this.items, i)
       end}
    end

    def reduce(this, acc, fun) do
      do_reduce(0, this.count, this, acc, fun)
    end

    defp do_reduce(_idx, _total, _this, {:halt, acc}, _fun), do: {:halted, acc}

    defp do_reduce(idx, total, this, {:suspend, acc}, fun),
      do: {:suspended, acc, &do_reduce(idx, total, this, &1, fun)}

    defp do_reduce(idx, total, _this, {:cont, acc}, _fun) when idx >= total, do: {:done, acc}

    defp do_reduce(idx, total, this, {:cont, acc}, fun) do
      value = Map.get(this.items, idx)

      case fun.(value, acc) do
        {:halt, acc2} -> {:halted, acc2}
        {:suspend, acc2} -> {:suspended, acc2, &do_reduce(idx + 1, total, this, &1, fun)}
        {:cont, acc2} -> do_reduce(idx + 1, total, this, {:cont, acc2}, fun)
      end
    end

    def member?(this, term) do
      {:ok, Enum.any?(Map.values(this.items), fn v -> v == term end)}
    end
  end
end
