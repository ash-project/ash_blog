defmodule AshBlogTest do
  use ExUnit.Case
  doctest AshBlog

  test "greets the world" do
    assert AshBlog.hello() == :world
  end
end
