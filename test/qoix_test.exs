defmodule QoixTest do
  use ExUnit.Case
  doctest Qoix

  test "greets the world" do
    assert Qoix.hello() == :world
  end
end
