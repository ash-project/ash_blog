defmodule AshBlog do
  @moduledoc """
  Documentation for `AshBlog`.
  """

  import XmlBuilder

  def rss_feed(blog_posts, opts \\ []) do
    blog_posts = Enum.filter(blog_posts, &(&1.state == :published))

    default_updated =
      blog_posts
      |> Enum.map(& &1.published_at)
      |> case do
        [] ->
          DateTime.utc_now()

        rows ->
          Enum.max(rows, DateTime)
      end

    element(
      :feed,
      %{xmlns: "http://www.w3.org/2005/Atom"},
      [
        element(:id, opts[:link]),
        element(:title, opts[:title]),
        element(:link, %{href: opts[:link], rel: "alternate", type: "text/html"}),
        element(:link, %{href: opts[:rss_link], rel: "self", type: "application/atom+xml"}),
        element(:updated, to_string(opts[:updated] || default_updated))
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

          element(:entry, data, inners)
        end)
    )
    |> XmlBuilder.generate()
  end
end
