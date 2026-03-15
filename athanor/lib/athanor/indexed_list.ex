defmodule Athanor.IndexedList do
  defstruct count: 0, items: %{}

  def add_all(il, items) do
    Enum.reduce(items, il, fn item, %__MODULE__{count: count, items: acc_items} ->
      %__MODULE__{count: count + 1, items: Map.put(acc_items, count, item)}
    end)
  end
end
