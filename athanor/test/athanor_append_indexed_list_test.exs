defmodule Athanor.AppendIndexedListTest do
  use ExUnit.Case, async: true

  alias Athanor.AppendIndexedList

  test "append single item and read by index" do
    a = %AppendIndexedList{}
    a = AppendIndexedList.append(a, :foo)

    assert AppendIndexedList.at(a, 0) == :foo
    assert AppendIndexedList.at(a, 1) == nil
  end

  test "append list of items preserves order" do
    a = %AppendIndexedList{}
    a = AppendIndexedList.append(a, [:a, :b, :c])

    assert Enum.to_list(a) == [:a, :b, :c]
    assert Enum.count(a) == 3
    assert Enum.member?(a, :b)
  end

  test "append does not allow nil items" do
    a = %AppendIndexedList{}

    assert_raise ArgumentError, fn ->
      AppendIndexedList.append(a, [1, nil, 3])
    end

    assert_raise ArgumentError, fn ->
      AppendIndexedList.append(a, nil)
    end
  end

  test "reduce works and preserves insertion order" do
    a = %AppendIndexedList{}
    a = AppendIndexedList.append(a, [1, 2, 3, 4])

    sum = Enum.reduce(a, 0, fn x, acc -> x + acc end)
    assert sum == 10
  end
end
