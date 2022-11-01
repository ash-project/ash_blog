defmodule AshBlog do
  @moduledoc """
  Documentation for `AshBlog`.
  """

  import XmlBuilder

  def rss_feed(blog_posts, opts \\ []) do
    blog_posts = Enum.filter(blog_posts, &(&1.state == :published))

    updated = opts[:updated] || fn blog_post -> blog_post.published_at end

    last_updated =
      blog_posts
      |> Enum.map(updated)
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
        element(:updated, DateTime.to_iso8601(last_updated))
      ] ++
        Enum.map(blog_posts, fn %resource{} = blog_post ->
          inners = [
            element(
              :id,
              Ash.Resource.Info.primary_key(resource)
              |> Enum.map_join("-", &to_string(Map.get(blog_post, &1)))
            ),
            element(:title, Map.get(blog_post, AshBlog.DataLayer.Info.title_attribute(resource))),
            element(:updated, DateTime.to_iso8601(updated.(blog_post)))
          ]

          inners =
            if opts[:linker] do
              [element(:link, %{rel: "alternate", href: opts[:linker].(blog_post)}) | inners]
            else
              inners
            end

          inners =
            if opts[:html_body] do
              [
                element(:content, %{type: "html"}, {:cdata, opts[:html_body].(blog_post)})
                | inners
              ]
            else
              inners
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

          element(:entry, inners)
        end)
    )
    |> XmlBuilder.generate()
  end
end
