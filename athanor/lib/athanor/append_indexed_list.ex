defmodule Athanor.AppendIndexedList do
  @type t() :: %__MODULE__{count: non_neg_integer(), items: map()}

  defstruct count: 0, items: %{}

  @spec append(t(), list(term())) :: t()
  def append(this, items) when is_list(items) do
    Enum.reduce(items, this, fn item, %__MODULE__{count: count, items: acc_items} ->
      %__MODULE__{count: count + 1, items: Map.put(acc_items, count, item)}
    end)
  end

  @spec append(t(), term()) :: t()
  def append(this, item) do
    append(this, [item])
  end

  @spec at(t(), non_neg_integer()) :: term() | nil
  def at(this, index) when is_integer(index) and index >= 0 do
    Map.get(this.items, index)
  end

  defimpl Enumerable do
    def count(this), do: {:ok, this.count}

    def slice(this) do
      {:ok, this.count,
       fn start, length ->
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

    def member?(this, term), do: {:ok, Enum.any?(Map.values(this.items), fn v -> v == term end)}
  end
end
