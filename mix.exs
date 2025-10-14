# SPDX-FileCopyrightText: 2022 ash_blog contributors <https://github.com/ash-project/ash_blog/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.MixProject do
  use Mix.Project

  @description """
  A blog data layer for Ash resources.
  """

  @version "0.1.0"

  def project do
    [
      app: :ash_blog,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      package: package(),
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [plt_add_apps: [:ash]],
      docs: docs(),
      description: @description,
      source_url: "https://github.com/ash-project/ash_blog",
      homepage_url: "https://github.com/ash-project/ash_blog"
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp docs do
    [
      main: "AshBlog",
      source_ref: "v#{@version}",
      extra_section: "GUIDES",
      extras: [],
      groups_for_extras: [],
      groups_for_modules: [
        "Resource DSL": ~r/AshGraphql.Resource/,
        "Api DSL": ~r/AshGraphql.Api/
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "Zach Daniel <zach@zachdaniel.dev>"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation),
      links: %{
        "GitHub" => "https://github.com/ash-project/ash_blog",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org",
        "Forum" => "https://elixirforum.com/c/ash-framework-forum/",
        "Changelog" => "https://github.com/ash-project/ash_blog/blob/main/CHANGELOG.md",
        "REUSE Compliance" => "https://api.reuse.software/info/github.com/ash-project/ash_blog"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sourceror, "~> 1.0", only: [:dev, :test]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:yaml_elixir, "~> 2.9"},
      {:xml_builder, "~> 2.2"},

      # dev/test dependencies
      {:ex_doc, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.0", only: [:dev, :test]},
      {:excoveralls, "~> 0.13", only: [:dev, :test]},
      {:mix_audit, "~> 2.1", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: ["docs", "spark.replace_doc_links"],
      "spark.formatter": "spark.formatter --extensions AshBlog.DataLayer"
    ]
  end
end
