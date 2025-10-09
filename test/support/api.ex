# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    allow_unregistered? true
  end
end
