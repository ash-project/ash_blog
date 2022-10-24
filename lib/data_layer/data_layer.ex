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
      folder: [
        type: :string,
        default: "static/blog",
        doc: """
        A path relative to to the priv directory where the files should be placed.
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
    transformers: [Ash.DataLayer.Transformers.RequirePreCheckWith]

  alias Ash.Actions.Sort

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :filter,
      :limit,
      :sort,
      :tenant,
      :api,
      calculations: [],
      aggregates: [],
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
  def can?(_, :multitenancy), do: true
  def can?(_, :upsert), do: true
  def can?(_, :aggregate_filter), do: true
  def can?(_, :aggregate_sort), do: true
  def can?(_, {:aggregate_relationship, _}), do: true
  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, {:aggregate, :count}), do: true
  def can?(_, :create), do: true
  def can?(_, :read), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
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
  def resource_to_query(resource, api) do
    %Query{
      resource: resource,
      api: api
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
  def set_tenant(_resource, query, tenant) do
    {:ok, %{query | tenant: tenant}}
  end

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
  def run_aggregate_query(%{api: api} = query, aggregates, resource) do
    case run_query(query, resource) do
      {:ok, results} ->
        Enum.reduce_while(aggregates, {:ok, %{}}, fn
          %{kind: :count, name: name, query: query}, {:ok, acc} ->
            results
            |> filter_matches(Map.get(query || %{}, :filter), api)
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
          tenant: tenant,
          calculations: calculations,
          aggregates: aggregates,
          api: api
        },
        _resource
      ) do
    with {:ok, records} <- get_records(resource, tenant),
         {:ok, records} <- do_add_aggregates(records, api, resource, aggregates),
         {:ok, records} <-
           filter_matches(records, filter, api),
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
            case Ash.Filter.Runtime.do_match(record, expression) do
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

  defp do_add_aggregates(records, _api, _resource, []), do: {:ok, records}

  defp do_add_aggregates(records, api, _resource, aggregates) do
    # TODO support crossing apis by getting the destination api, and set destination query context.
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, records} ->
      aggregates
      |> Enum.reduce_while({:ok, record}, fn %{
                                               kind: :count,
                                               relationship_path: relationship_path,
                                               query: query,
                                               authorization_filter: authorization_filter,
                                               name: name,
                                               load: load
                                             },
                                             {:ok, record} ->
        query =
          if authorization_filter do
            Ash.Query.do_filter(query, authorization_filter)
          else
            query
          end

        with {:ok, loaded_record} <- api.load(record, relationship_path),
             related <- Ash.Filter.Runtime.get_related(loaded_record, relationship_path),
             {:ok, filtered} <-
               filter_matches(related, query.filter, api) do
          {:cont, {:ok, Map.put(record, load || name, Enum.count(filtered))}}
        else
          other ->
            {:halt, other}
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

  defp get_records(resource, tenant) do
    with {:ok, table} <- wrap_or_create_table(resource, tenant),
         {:ok, record_tuples} <- ETS.Set.to_list(table),
         records <- Enum.map(record_tuples, &elem(&1, 1)) do
      cast_records(records, resource)
    end
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
         %{
           struct(resource, attrs)
           | __meta__: %Ecto.Schema.Metadata{state: :loaded, schema: resource}
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp filter_matches(records, nil, _api), do: {:ok, records}

  defp filter_matches(records, filter, api) do
    Ash.Filter.Runtime.filter_matches(api, records, filter)
  end

  @doc false
  @impl true
  def upsert(resource, changeset, keys) do
    keys = keys || Ash.Resource.Info.primary_key(resource)

    if Enum.any?(keys, &is_nil(Ash.Changeset.get_attribute(changeset, &1))) do
      create(resource, changeset)
    else
      key_filters =
        Enum.map(keys, fn key ->
          {key, Ash.Changeset.get_attribute(changeset, key)}
        end)

      query = Ash.Query.do_filter(resource, and: [key_filters])

      resource
      |> resource_to_query(changeset.api)
      |> Map.put(:filter, query.filter)
      |> Map.put(:tenant, changeset.tenant)
      |> run_query(resource)
      |> case do
        {:ok, []} ->
          create(resource, changeset)

        {:ok, [result]} ->
          to_set = Ash.Changeset.set_on_upsert(changeset, keys)

          changeset =
            changeset
            |> Map.put(:attributes, %{})
            |> Map.put(:data, result)
            |> Ash.Changeset.force_change_attributes(to_set)

          update(resource, changeset)

        {:ok, _} ->
          {:error, "Multiple records matching keys"}
      end
    end
  end

  @doc false
  @impl true
  def create(resource, changeset) do
    pkey =
      resource
      |> Ash.Resource.Info.primary_key()
      |> Enum.into(%{}, fn attr ->
        {attr, Ash.Changeset.get_attribute(changeset, attr)}
      end)

    with {:ok, table} <- wrap_or_create_table(resource, changeset.tenant),
         {:ok, record} <- Ash.Changeset.apply_attributes(changeset),
         record <- unload_relationships(resource, record),
         {:ok, record} <-
           put_or_insert_new(table, {pkey, record}, resource) do
      {:ok, %{record | __meta__: %Ecto.Schema.Metadata{state: :loaded, schema: resource}}}
    else
      {:error, error} -> {:error, Ash.Error.to_ash_error(error)}
    end
  end

  defp put_or_insert_new(table, {pkey, record}, resource) do
    attributes = resource |> Ash.Resource.Info.attributes()

    case dump_to_native(record, attributes) do
      {:ok, casted} ->
        case ETS.Set.put(table, {pkey, casted}) do
          {:ok, set} ->
            {_key, record} = ETS.Set.get!(set, pkey)
            cast_record(record, resource)

          other ->
            other
        end

      other ->
        other
    end
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
  def destroy(resource, %{data: record} = changeset) do
    do_destroy(resource, record, changeset.tenant)
  end

  defp do_destroy(resource, record, tenant) do
    pkey = Map.take(record, Ash.Resource.Info.primary_key(resource))

    with {:ok, table} <- wrap_or_create_table(resource, tenant),
         {:ok, _} <- ETS.Set.delete(table, pkey) do
      :ok
    else
      {:error, error} -> {:error, Ash.Error.to_ash_error(error)}
    end
  end

  @doc false
  @impl true
  def update(resource, changeset) do
    pkey = pkey_map(resource, changeset.data)

    with {:ok, table} <- wrap_or_create_table(resource, changeset.tenant),
         {:ok, record} <- Ash.Changeset.apply_attributes(changeset),
         {:ok, record} <-
           do_update(table, {pkey, record}, resource),
         {:ok, record} <- cast_record(record, resource) do
      new_pkey = pkey_map(resource, record)

      if new_pkey != pkey do
        case destroy(resource, changeset) do
          :ok ->
            {:ok, %{record | __meta__: %Ecto.Schema.Metadata{state: :loaded, schema: resource}}}

          {:error, error} ->
            {:error, Ash.Error.to_ash_error(error)}
        end
      else
        {:ok, %{record | __meta__: %Ecto.Schema.Metadata{state: :loaded, schema: resource}}}
      end
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

  defp do_update(table, {pkey, record}, resource) do
    attributes = resource |> Ash.Resource.Info.attributes()

    case dump_to_native(record, attributes) do
      {:ok, casted} ->
        case ETS.Set.get(table, pkey) do
          {:ok, {_key, record}} when is_map(record) ->
            case ETS.Set.put(table, {pkey, Map.merge(record, casted)}) do
              {:ok, set} ->
                {_key, record} = ETS.Set.get!(set, pkey)
                {:ok, record}

              error ->
                error
            end

          {:ok, _} ->
            {:error, "Record not found matching: #{inspect(pkey)}"}

          other ->
            other
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def transaction(resource, fun, timeout \\ :infinity) do
    folder = folder(resource)

    :global.trans(
      {{:csv, folder}, System.unique_integer()},
      fn ->
        try do
          Process.put({:blog_in_transaction, folder}, true)
          {:res, fun.()}
        catch
          {{:csv_rollback, ^folder}, value} ->
            {:error, value}
        end
      end,
      [node() | :erlang.nodes()],
      timeout
    )
    |> case do
      {:res, result} -> {:ok, result}
      {:error, error} -> {:error, error}
      :aborted -> {:error, "transaction failed"}
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:blog_rollback, file(resource)}, error})
  end

  @impl true
  def in_transaction?(resource) do
    Process.get({:blog_in_transaction, file(resource)}, false) == true
  end
end
