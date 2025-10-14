# SPDX-FileCopyrightText: 2022 ash_blog contributors <https://github.com/ash-project/ash_blog/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Used by "mix format"
spark_locals_without_parens = [
  archive_folder: 1,
  body_attribute: 1,
  created_at_attribute: 1,
  file_namer: 1,
  folder: 1,
  slug_attribute: 1,
  staging_folder: 1,
  title_attribute: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ash, :spark],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
