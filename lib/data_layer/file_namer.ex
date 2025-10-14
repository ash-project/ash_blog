# SPDX-FileCopyrightText: 2022 ash_blog contributors <https://github.com/ash-project/ash_blog/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.FileNamer do
  @moduledoc """
  The default file namer, uses the current timestamp and the title attribute of the post in the form `YYYY/YYYY-MM-DD-name.md`
  """
  def name_file(changeset) do
    name =
      case Ash.Changeset.get_attribute(
             changeset,
             AshBlog.DataLayer.Info.title_attribute(changeset.resource)
           ) do
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
