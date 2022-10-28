defmodule AshBlogTest do
  use ExUnit.Case

  alias AshBlog.Test.Post

  setup do
    on_exit(fn ->
      File.rm_rf!("priv/blog")
      File.rm_rf!("priv/static/blog")
    end)

    :ok
  end

  describe "creating a blog post" do
    test "a blog post can be created" do
      assert %{title: "first\"", body: "the body"} = Post.create!("first\"", "the body")
    end
  end

  describe "reading blog posts" do
    test "blog posts can be listed" do
      Post.create!("first\"", "the body")
      assert [%{title: "first\"", body: "the body"}] = Post.read!()
    end
  end

  describe "updating blog posts" do
    test "blog posts can be published" do
      post = Post.create!("first\"", "the body")
      assert %{state: :published} = Post.publish!(post)
      assert [%{state: :published, title: "first\"", body: "the body"}] = Post.read!()
      assert [_] = Path.wildcard("priv/static/blog/**/*.md")
    end

    test "blog posts can be archived" do
      post = Post.create!("first\"", "the body")
      assert %{state: :published} = Post.publish!(post)
      assert [%{state: :published, title: "first\"", body: "the body"} = post] = Post.read!()
      assert [_] = Path.wildcard("priv/static/blog/**/*.md")
      assert %{state: :archived} = Post.archive!(post)
      assert [_] = Path.wildcard("priv/blog/archive/**/*.md")
    end
  end
end
