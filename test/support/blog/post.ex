defmodule AshBlog.Test.Post do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_blog,
    data_layer: AshBlog.DataLayer

  actions do
    defaults [:create, :read]
  end

  attributes do
    uuid_primary_key :id
  end

  code_interface do
    define_for AshBlog.Test.Api
    define :create, args: [:title, :body]
    define :read, action: :read
    define :stage, action: :stage
    define :publish, action: :publish
    define :archive, action: :archive
  end
end
