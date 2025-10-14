# SPDX-FileCopyrightText: 2022 ash_blog contributors <https://github.com/ash-project/ash_blog/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    allow_unregistered? true
  end
end
