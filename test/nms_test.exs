defmodule NmsTest do
  use ExUnit.Case
  doctest Nms

  test "greets the world" do
    assert Nms.hello() == :world
  end
end
