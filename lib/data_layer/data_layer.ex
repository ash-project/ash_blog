# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshBlog.DataLayer do
  @behaviour Ash.DataLayer

  @blog %Spark.Dsl.Section{
    name: :blog,
    describe: """
    A section for configuring the blog data layer
    """,
    examples: [
      """
      blog do
      end
      """
    ],
    links: [],
    schema: [
      file_namer: [
        type: :mfa,
        default: {AshBlog.FileNamer, :name_file, []},
        doc: """
        An MFA that will take a changeset and produce a file name.
        The default one looks for a title or name, and appends it to `YYYY/YYYY-MM-DD-\#\{dasherized_name\}.md`.
        The date uses the time that the file name was generated record.
        """
      ],
      title_attribute: [
        type: :atom,
        default: :title,
        doc:
          "The attribute name to use for the title of the blog post. Will be created if it doesn't exist."
      ],
      created_at_attribute: [
        type: :atom,
        default: :created_at,
        doc:
          "The attribute name to use for the created_at timestamp of the blog post. Will be created if it doesn't exist."
      ],
      body_attribute: [
        type: :atom,
        default: :body,
        doc:
          "The attribute name to use for the body of the post. Wil be created if it doesn't exist."
      ],
      slug_attribute: [
        type: :atom,
        default: :slug,
        doc:
          "The attribute name to use for the slug. All past slugs will be stored and used when looking up by slug."
      ],
      folder: [
        type: :string,
        default: "blog/published",
        doc: """
        A path relative to to the priv directory where the files should be placed.
        """
      ],
      staging_folder: [
        type: :string,
        default: "blog/staged",
        doc: """
        A path relative to to the priv directory where the staged files should be placed when they are staged.
        """
      ],
      archive_folder: [
        type: :string,
        default: "blog/archived",
        doc: """
        A path relative to to the priv directory where the archived files should be placed when they are staged.
        """
      ]
    ]
  }

  @moduledoc """
  A blog data layer backed by markdown files.

  <!--- ash-hq-hide-start--> <!--- -->

  ## DSL Documentation

  ### Index

  #{Spark.Dsl.Extension.doc_index([@blog])}

  ### Docs

  #{Spark.Dsl.Extension.doc([@blog])}
  <!--- ash-hq-hide-stop--> <!--- -->
  """

  use Spark.Dsl.Extension,
    sections: [@blog],
    transformers: [AshBlog.DataLayer.Transformers.AddStructure]

  alias Ash.Actions.Sort

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :filter,
      :limit,
      :sort,
      :domain,
      calculations: [],
      relationships: %{},
      offset: 0
    ]
  end

  @doc false
  @impl true
  def can?(_, :async_engine), do: true

  def can?(_, :composite_primary_key), do: true
  def can?(_, :expression_calculation), do: true
  def can?(_, :expression_calculation_sort), do: true
  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, :create), do: true
  def can?(_, :read), do: true
  def can?(_, :update), do: true
  # Destroy is not implemented yet, because I didn't need it
  def can?(_, :destroy), do: false
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, {:query_aggregate, :count}), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, :transact), do: true
  def can?(_, _), do: false

  @doc false
  @impl true
  def resource_to_query(resource, domain) do
    %Query{
      resource: resource,
      domain: domain
    }
  end

  @doc false
  @impl true
  def limit(query, limit, _), do: {:ok, %{query | limit: limit}}

  @doc false
  @impl true
  def offset(query, offset, _), do: {:ok, %{query | offset: offset}}

  @doc false
  @impl true
  def add_calculation(query, calculation, _, _),
    do: {:ok, %{query | calculations: [calculation | query.calculations]}}

  @doc false
  @impl true
  def add_aggregate(query, aggregate, _),
    do: {:ok, %{query | aggregates: [aggregate | query.aggregates]}}

  @doc false
  @impl true
  def filter(query, filter, _resource) do
    if query.filter do
      {:ok, %{query | filter: Ash.Filter.add_to_filter!(query.filter, filter)}}
    else
      {:ok, %{query | filter: filter}}
    end
  end

  @doc false
  @impl true
  def sort(query, sort, _resource) do
    {:ok, %{query | sort: sort}}
  end

  @doc false
  @impl true
  def run_aggregate_query(%{domain: domain} = query, aggregates, resource) do
    case run_query(query, resource) do
      {:ok, results} ->
        Enum.reduce_while(aggregates, {:ok, %{}}, fn
          %{kind: :count, name: name, query: query}, {:ok, acc} ->
            results
            |> filter_matches(Map.get(query || %{}, :filter), domain)
            |> case do
              {:ok, matches} ->
                {:cont, {:ok, Map.put(acc, name, Enum.count(matches))}}

              {:error, error} ->
                {:halt, {:error, error}}
            end

          _, _ ->
            {:halt, {:error, "unsupported aggregate"}}
        end)

      {:error, error} ->
        {:error, error}
    end
    |> case do
      {:error, error} ->
        {:error, Ash.Error.to_ash_error(error)}

      other ->
        other
    end
  end

  @doc false
  @impl true
  def run_query(
        %Query{
          resource: resource,
          filter: filter,
          offset: offset,
          limit: limit,
          sort: sort,
          calculations: calculations,
          domain: domain
        },
        _resource
      ) do
    with {:ok, records} <- get_records(resource),
         {:ok, records} <-
           filter_matches(records, filter, domain),
         {:ok, records} <-
           do_add_calculations(records, resource, calculations) do
      offset_records =
        records
        |> Sort.runtime_sort(sort)
        |> Enum.drop(offset || 0)

      if limit do
        {:ok, Enum.take(offset_records, limit)}
      else
        {:ok, offset_records}
      end
    else
      {:error, error} ->
        {:error, Ash.Error.to_ash_error(error)}
    end
  end

  defp do_add_calculations(records, _resource, []), do: {:ok, records}

  defp do_add_calculations(records, resource, calculations) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, records} ->
      calculations
      |> Enum.reduce_while({:ok, record}, fn calculation, {:ok, record} ->
        expression = calculation.module.expression(calculation.opts, calculation.context)

        case Ash.Filter.hydrate_refs(expression, %{
               resource: resource,
               public?: false
             }) do
          {:ok, expression} ->
            case Ash.Expr.eval_hydrated(expression, record: record) do
              {:ok, value} ->
                if calculation.load do
                  {:cont, {:ok, Map.put(record, calculation.load, value)}}
                else
                  {:cont,
                   {:ok,
                    Map.update!(record, :calculations, &Map.put(&1, calculation.name, value))}}
                end

              :unknown ->
                if calculation.load do
                  {:cont, {:ok, Map.put(record, calculation.load, nil)}}
                else
                  {:cont,
                   {:ok, Map.update!(record, :calculations, &Map.put(&1, calculation.name, nil))}}
                end

              {:error, error} ->
                {:halt, {:error, error}}
            end

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, record} ->
          {:cont, {:ok, [record | records]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, records} ->
        {:ok, Enum.reverse(records)}

      {:error, error} ->
        {:error, Ash.Error.to_ash_error(error)}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp get_records(resource) do
    published =
      resource
      |> AshBlog.DataLayer.Info.folder()
      |> all_files(resource)

    staged =
      resource
      |> AshBlog.DataLayer.Info.staging_folder()
      |> all_files(resource)

    archived =
      resource
      |> AshBlog.DataLayer.Info.archive_folder()
      |> all_files(resource)

    [published, staged, archived]
    |> Stream.concat()
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, results} ->
      contents = File.read!(file)

      [data, body] =
        contents
        |> String.split("---", trim: true)
        |> Enum.map(&String.trim/1)

      case YamlElixir.read_all_from_string(data, one_result: true) do
        {:ok, result} ->
          attrs =
            resource
            |> Ash.Resource.Info.attributes()
            |> Map.new(fn attr ->
              {attr.name, decode_formatting_hacks(Map.get(result, to_string(attr.name)))}
            end)
            |> Map.put(AshBlog.DataLayer.Info.body_attribute(resource), body)

          resource
          |> struct(attrs)
          |> cast_record(resource)
          |> case do
            {:ok, record} ->
              {:cont, {:ok, [Ash.Resource.put_metadata(record, :ash_blog_file, file) | results]}}

            {:error, error} ->
              {:error, error}
          end

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  @doc false
  def cast_records(records, resource) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, casted} ->
      case cast_record(record, resource) do
        {:ok, casted_record} ->
          {:cont, {:ok, [casted_record | casted]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, records} ->
        {:ok, Enum.reverse(records)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp decode_formatting_hacks(value) when is_list(value) do
    Enum.map(value, &decode_formatting_hacks/1)
  end

  defp decode_formatting_hacks(value) when is_binary(value) do
    # I hate this more than words can describe
    value
    |> String.replace("__ash_blog_single_quote_hack__", ",")
    |> String.replace("__ash_blog_newline_hack__", "\n")
  end

  defp decode_formatting_hacks(value), do: value

  @doc false
  def cast_record(record, resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reduce_while({:ok, %{}}, fn attribute, {:ok, attrs} ->
      case Map.get(record, attribute.name) do
        nil ->
          {:cont, {:ok, Map.put(attrs, attribute.name, nil)}}

        value ->
          case Ash.Type.cast_stored(attribute.type, value, attribute.constraints) do
            {:ok, value} ->
              {:cont, {:ok, Map.put(attrs, attribute.name, value)}}

            :error ->
              {:halt,
               {:error, "Failed to load #{inspect(value)} as type #{inspect(attribute.type)}"}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
      end
    end)
    |> case do
      {:ok, attrs} ->
        {:ok,
         Ash.Resource.set_meta(struct(resource, attrs), %Ecto.Schema.Metadata{
           state: :loaded,
           schema: resource
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  defp expand_path(folder, resource) do
    Path.join([priv_dir(resource), folder])
  end

  defp all_files(folder, resource) do
    Path.wildcard(Path.join([expand_path(folder, resource), "**", "*.md"]))
  end

  defp filter_matches(records, nil, _domain), do: {:ok, records}

  defp filter_matches(records, filter, domain) do
    Ash.Filter.Runtime.filter_matches(domain, records, filter)
  end

  @doc false
  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def create(resource, changeset) do
    file_name = file_name(resource, changeset)

    file_path =
      resource
      |> priv_dir()
      |> Path.join(folder(resource, Ash.Changeset.get_attribute(changeset, :state)))
      |> Path.join(file_name)

    with {:ok, record} <- Ash.Changeset.apply_attributes(changeset),
         record <-
           Ash.Resource.set_meta(record, %Ecto.Schema.Metadata{state: :loaded, schema: resource}),
         {:ok, yaml} <- yaml_frontmatter(record) do
      File.mkdir_p!(Path.dirname(file_path))

      File.write!(
        file_path,
        """
        ---
        #{yaml}
        ---
        #{Map.get(record, AshBlog.DataLayer.Info.body_attribute(resource))}
        """
      )

      {:ok, Ash.Resource.put_metadata(record, :ash_blog_file, file_path)}
    end
  end

  defp folder(resource, :staged) do
    AshBlog.DataLayer.Info.staging_folder(resource)
  end

  defp folder(resource, :published) do
    AshBlog.DataLayer.Info.folder(resource)
  end

  defp folder(resource, :archived) do
    AshBlog.DataLayer.Info.archive_folder(resource)
  end

  defp yaml_frontmatter(%resource{} = record) do
    body_attribute = AshBlog.DataLayer.Info.body_attribute(resource)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reject(&(&1.name == body_attribute))
    |> Enum.reduce_while({:ok, []}, fn attr, {:ok, acc} ->
      storage_type = Ash.Type.storage_type(unwrap_array(attr.type))

      if storage_type in [
           :string,
           :ci_string,
           :integer,
           :uuid,
           :utc_datetime,
           :utc_datetime_usec
         ] do
        case Ash.Type.dump_to_embedded(attr.type, Map.get(record, attr.name), attr.constraints) do
          {:ok, value} ->
            {:cont, {:ok, [{attr.name, value} | acc]}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      else
        {:halt,
         {:error,
          "#{inspect(attr.type)} with storage type #{inspect(storage_type)} is not yet supported by `AshBlog.DataLayer`"}}
      end
    end)
    |> case do
      {:ok, attrs} ->
        {:ok,
         attrs
         |> Enum.reverse()
         |> Enum.map_join("\n", fn {name, value} ->
           "#{name}: #{encode(value)}"
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  def encode(value, indentation \\ 2) do
    case value do
      value when is_binary(value) ->
        "'#{escape_string(value)}'"

      %DateTime{} = value ->
        "'#{escape_string(value)}'"

      [] ->
        "[]"

      list when is_list(value) ->
        "\n#{listify(list, indentation)}"

      other ->
        to_string(other)
    end
  end

  def listify(value, indentation \\ 2) do
    Enum.map_join(value, "\n", fn value ->
      "#{String.duplicate(" ", indentation)}- #{encode(value, indentation + 2)}"
    end)
  end

  defp unwrap_array({:array, value}), do: unwrap_array(value)
  defp unwrap_array(value), do: value

  defp escape_string(value) do
    value
    |> to_string()
    |> String.replace("'", "__ash_blog_single_quote_hack__")
    |> String.replace("\n", "__ash_blog_newline_hack__")
  end

  case Code.ensure_compiled(Mix) do
    {:module, _} ->
      def priv_dir(resource) do
        _ = otp_app!(resource)
        Path.join(File.cwd!(), "priv")
      end

    _ ->
      def priv_dir(resource) do
        :code.priv_dir(otp_app!(resource))
      end
  end

  defp otp_app!(resource) do
    Spark.otp_app(resource) ||
      raise """
      Must configure otp_app for #{inspect(resource)}. For example:

        use Ash.Resource, otp_app: :my_app
      """
  end

  defp file_name(resource, changeset) do
    {m, f, a} = AshBlog.DataLayer.Info.file_namer(resource)
    apply(m, f, [changeset | a])
  end

  @doc false
  def dump_to_native(record, attributes) do
    Enum.reduce_while(attributes, {:ok, %{}}, fn attribute, {:ok, attrs} ->
      case Map.get(record, attribute.name) do
        nil ->
          {:cont, {:ok, Map.put(attrs, attribute.name, nil)}}

        value ->
          case Ash.Type.dump_to_native(
                 attribute.type,
                 value,
                 attribute.constraints
               ) do
            {:ok, casted_value} ->
              {:cont, {:ok, Map.put(attrs, attribute.name, casted_value)}}

            :error ->
              {:halt,
               {:error,
                "Failed to dump #{inspect(Map.get(record, attribute.name))} as type #{inspect(attribute.type)}"}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
      end
    end)
  end

  @doc false
  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def update(resource, changeset) do
    with {:ok, record} <-
           do_update(changeset, resource),
         {:ok, record} <- cast_record(record, resource) do
      file_path =
        if folder(resource, record.state) == folder(resource, changeset.data.state) do
          changeset.data.__metadata__[:ash_blog_file]
        else
          new_file_path =
            Path.join(
              folder(resource, record.state),
              Path.basename(changeset.data.__metadata__[:ash_blog_file])
            )
            |> expand_path(resource)

          File.mkdir_p!(Path.dirname(new_file_path))

          File.rename!(
            changeset.data.__metadata__[:ash_blog_file],
            new_file_path
          )

          new_file_path
        end

      {:ok,
       record
       |> Ash.Resource.put_metadata(:ash_blog_file, file_path)
       |> Ash.Resource.set_meta(%Ecto.Schema.Metadata{state: :loaded, schema: resource})}
    else
      {:error, error} ->
        {:error, Ash.Error.to_ash_error(error)}
    end
  end

  @doc false
  def pkey_map(resource, data) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.into(%{}, fn attr ->
      {attr, Map.get(data, attr)}
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_update(changeset, resource) do
    file_path =
      changeset.data.__metadata__[:ash_blog_file] ||
        raise "Missing `ash_blog_file` metadata for record, cannot update!"

    with {:ok, record} <- Ash.Changeset.apply_attributes(changeset),
         record <-
           Ash.Resource.set_meta(record, %Ecto.Schema.Metadata{state: :loaded, schema: resource}),
         {:ok, yaml} <- yaml_frontmatter(record) do
      File.mkdir_p!(Path.dirname(file_path))

      File.write!(
        file_path,
        """
        ---
        #{yaml}
        ---
        #{Map.get(record, AshBlog.DataLayer.Info.body_attribute(resource))}
        """
      )

      {:ok, Ash.Resource.put_metadata(record, :ash_blog_file, file_path)}
    end
  end

  @impl true
  def transaction(resource, fun, _timeout, _) do
    tx_identifiers = tx_identifiers(resource)

    all_in_transaction(tx_identifiers, fn ->
      try do
        {:ok, fun.()}
      catch
        {{:blog_rollback, rolled_back_tx_identifiers}, value} = thrown ->
          if Enum.any?(tx_identifiers, &(&1 in rolled_back_tx_identifiers)) do
            {:error, value}
          else
            throw(thrown)
          end
      end
    end)
  end

  defp all_in_transaction([], fun) do
    fun.()
  end

  defp all_in_transaction([tx_identifier | rest], fun) do
    :global.trans(
      {{:blog, tx_identifier}, System.unique_integer()},
      fn ->
        Process.put({:blog_in_transaction, tx_identifier}, true)
        all_in_transaction(rest, fun)
      end,
      [node() | :erlang.nodes()],
      0
    )
    |> case do
      :aborted -> {:error, "transaction failed"}
      result -> result
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:blog_rollback, tx_identifiers(resource)}, error})
  end

  @impl true
  def in_transaction?(resource) do
    resource
    |> tx_identifiers()
    |> Enum.any?(fn identifier ->
      Process.get({:blog_in_transaction, identifier}, false) == true
    end)
  end

  defp tx_identifiers(resource) do
    [
      AshBlog.DataLayer.Info.folder(resource),
      AshBlog.DataLayer.Info.staging_folder(resource),
      AshBlog.DataLayer.Info.archive_folder(resource)
    ]
  end
end
