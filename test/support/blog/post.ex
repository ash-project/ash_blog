# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.Test.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshBlog.Test.Domain,
    otp_app: :ash_blog,
    data_layer: AshBlog.DataLayer

  actions do
    default_accept :*
    defaults [:create, :read, :update]
  end

  attributes do
    uuid_primary_key :id
  end

  code_interface do
    define :create, args: [:title, :body]
    define :read, action: :read
    define :stage, action: :stage
    define :publish, action: :publish
    define :archive, action: :archive
  end
end
