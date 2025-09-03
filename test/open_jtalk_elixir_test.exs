defmodule OpenJtalkElixirTest do
  use ExUnit.Case
  doctest OpenJtalkElixir

  test "greets the world" do
    assert OpenJtalkElixir.hello() == :world
  end
end
