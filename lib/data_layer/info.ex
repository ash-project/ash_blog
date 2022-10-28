defmodule AshBlog.DataLayer.Info do
  @moduledoc """
  Introspection helpers for the AshBlog data layer.
  """

  alias Spark.Dsl.Extension

  def folder(resource) do
    Extension.get_opt(resource, [:blog], :folder, "static/blog")
  end

  def staging_folder(resource) do
    Extension.get_opt(resource, [:blog], :staging_folder, "blog/staging")
  end

  def archive_folder(resource) do
    Extension.get_opt(resource, [:blog], :archive_folder, "blog/archive")
  end

  def file_namer(resource) do
    Extension.get_opt(resource, [:blog], :file_namer, {AshBlog.FileNamer, :name_file, []})
  end

  def created_at_attribute(resource) do
    Extension.get_opt(resource, [:blog], :created_at_attribute, :created_at)
  end

  def body_attribute(resource) do
    Extension.get_opt(resource, [:blog], :body_attribute, :body)
  end

  def title_attribute(resource) do
    Extension.get_opt(resource, [:blog], :title_attribute, :title)
  end

  def file_name(%resource{} = record) do
    {mod, fun, args} = file_name(resource)

    case apply(mod, fun, [record | args]) do
      {:ok, value} ->
        {:ok, value}

      {:error, error} ->
        {:error, error}

      value ->
        raise """
        Invalid value returned from file namer `#{inspect(mod)}.#{fun}/#{Enum.count(args) + 1}`.

        Expected `{:ok, value}` or `{:error, error}`, got:

        #{inspect(value)}
        """
    end
  end

  def full_file_name(resource) do
    Path.join([folder(resource), file_name(resource)])
  end
end
