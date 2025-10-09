# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.DataLayer.Changes.SetAndTrackSlug do
  @moduledoc false
  use Ash.Resource.Change

  def change(changeset, _, _) do
    slug_attribute = AshBlog.DataLayer.Info.slug_attribute(changeset.resource)

    if changeset.action_type == :create do
      if Ash.Changeset.get_attribute(changeset, :slug) do
        changeset
      else
        set_default_slug(changeset, slug_attribute)
      end
    else
      if Ash.Changeset.changing_attribute?(changeset, slug_attribute) && changeset.data.slug do
        past_slugs = Ash.Changeset.get_attribute(changeset, :past_slugs) || []

        Ash.Changeset.force_change_attribute(changeset, :past_slugs, [
          changeset.data.slug | past_slugs
        ])
      else
        changeset
      end
    end
  end

  defp set_default_slug(changeset, slug_attribute) do
    title_attribute = AshBlog.DataLayer.Info.title_attribute(changeset.resource)

    Ash.Changeset.force_change_attribute(
      changeset,
      slug_attribute,
      to_slug(Ash.Changeset.get_attribute(changeset, title_attribute))
    )
  end

  defp to_slug(nil), do: nil

  defp to_slug(title) do
    title
    |> String.replace(~r/\s+/, " ")
    |> String.replace(" ", "-")
    |> String.replace(~r/[^A-Za-z0-9-]/, "")
    |> String.downcase()
  end
end
