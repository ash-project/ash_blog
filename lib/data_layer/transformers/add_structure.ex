defmodule AshBlog.DataLayer.Transformers.AddStructure do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshBlog.DataLayer.Info

  def transform(dsl_state) do
    dsl_state
    |> Ash.Resource.Builder.add_new_create_timestamp(Info.created_at_attribute(dsl_state))
    |> Ash.Resource.Builder.add_new_attribute(Info.title_attribute(dsl_state), :string,
      allow_nil?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(Info.slug_attribute(dsl_state), :string,
      allow_nil?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(:past_slugs, {:array, :string},
      allow_nil?: false,
      default: [],
      writable?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(Info.body_attribute(dsl_state), :string,
      allow_nil?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(:state, :atom,
      constraints: [one_of: [:staged, :published, :archived]],
      default: :staged,
      writable?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(:published_at, :utc_datetime_usec, writable?: false)
    |> Ash.Resource.Builder.add_change(AshBlog.DataLayer.Changes.SetAndTrackSlug,
      on: [:create, :update]
    )
    |> Ash.Resource.Builder.add_new_action(:update, :publish,
      accept: [],
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :published)
        ),
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:published_at, &DateTime.utc_now/0)
        )
      ]
    )
    |> Ash.Resource.Builder.add_new_action(:update, :stage,
      accept: [],
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :staged)
        )
      ]
    )
    |> Ash.Resource.Builder.add_new_action(:update, :archive,
      accept: [],
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :archived)
        )
      ]
    )
  end
end
