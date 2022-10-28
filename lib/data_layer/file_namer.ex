defmodule AshBlog.FileNamer do
  def name_file(changeset) do
    name =
      case Ash.Changeset.get_attribute(changeset, :title) ||
             Ash.Changeset.get_attribute(changeset, :name) do
        nil ->
          nil

        name ->
          name
          |> String.replace(~r/[^a-zA-Z0-9 _]/, "")
          |> String.replace(~r/[^a-zA-Z0-9]/, "-")
          |> String.trim("-")
      end

    if name do
      Calendar.strftime(
        DateTime.utc_now(),
        Path.join(["%Y", "%Y-%m-%d-#{name}.md"])
      )
    else
      Calendar.strftime(
        DateTime.utc_now(),
        Path.join(["%Y", "%Y-%m-%d.md"])
      )
    end
  end
end
