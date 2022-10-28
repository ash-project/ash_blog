defmodule AshBlog.DataLayer.Transformers.AddStructure do
  use Spark.Dsl.Transformer

  alias AshBlog.DataLayer.Info

  def transform(dsl_state) do
    dsl_state
    |> Ash.Resource.Builder.add_new_create_timestamp(Info.created_at_attribute(dsl_state))
    |> Ash.Resource.Builder.add_new_attribute(Info.title_attribute(dsl_state), :string,
      allow_nil?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(Info.body_attribute(dsl_state), :string,
      allow_nil?: false
    )
    |> Ash.Resource.Builder.add_new_attribute(:state, :atom,
      constraints: [one_of: [:staged, :published, :archived]],
      default: :staged
    )
    |> Ash.Resource.Builder.add_new_action(:update, :publish,
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :published)
        )
      ]
    )
    |> Ash.Resource.Builder.add_new_action(:update, :stage,
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :staged)
        )
      ]
    )
    |> Ash.Resource.Builder.add_new_action(:update, :archive,
      changes: [
        Ash.Resource.Builder.build_action_change(
          Ash.Resource.Change.Builtins.set_attribute(:state, :archived)
        )
      ]
    )
  end
end
