defmodule AshBlog do
  @moduledoc """
  Documentation for `AshBlog`.
  """

  import XmlBuilder

  def rss_feed(blog_posts, opts \\ []) do
    blog_posts = Enum.filter(blog_posts, &(&1.state == :published))

    element(
      :feed,
      %{xmlns: "http://www.w3.org/2005/Atom"},
      [
        element(:title, "Ash Framework Blog"),
        element(:link, "https://ash-hq.org/blog"),
        element(
          :description,
          "News and information about Ash Framework, a declarative, resource oriented Elixir application development framework."
        )
      ] ++
        Enum.map(blog_posts, fn %resource{} = blog_post ->
          data = [
            title: Map.get(blog_post, AshBlog.DataLayer.Info.title_attribute(resource))
          ]

          data =
            if opts[:linker] do
              Keyword.put(data, :link, opts[:linker].(blog_post))
            else
              data
            end

          inners =
            if opts[:html_body] do
              [element(:content, %{type: "html"}, {:cdata, opts[:html_body].(blog_post)})]
            else
              []
            end

          inners =
            if opts[:summary] do
              [element(:summary, %{type: "html"}, {:cdata, opts[:summary].(blog_post)}) | inners]
            else
              inners
            end

          inners =
            if opts[:author] do
              [element(:author, name: opts[:author].(blog_post)) | inners]
            else
              inners
            end

          data =
            Keyword.put(
              data,
              :id,
              Ash.Resource.Info.primary_key(resource)
              |> Enum.map_join("-", &to_string(Map.get(blog_post, &1)))
            )

          element(:item, data, inners)
        end)
    )
    |> XmlBuilder.generate()
  end
end
