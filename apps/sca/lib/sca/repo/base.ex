defmodule Sca.Repo.Base do
  @moduledoc """
  What every repository does the same way.

      defmodule Sca.Repos.TenantRepo do
        use Sca.Repo.Base, model: Sca.Models.Tenant
      end

  Gives the repo `create/1`, `update/2`, `change/2`, `get/1`, `get!/1`,
  `get_by/1`, `get_by_public_id/1`, `lock_by/1`, `list/1` (Flop), `list_by/2`,
  `list_all/0` and `delete/1`, all with specs. A model that creates through a
  different changeset says so:

      use Sca.Repo.Base, model: Sca.Models.User, create_changeset: :registration_changeset

  Lookups answer `{:ok, record} | {:error, :not_found}`, never a bare `nil`, so
  actions can chain them in a `with`. `get_by_public_id/1` refuses an id whose
  prefix belongs to another entity without a round trip: a `BIN-1` typed into a
  tenant field cannot match by accident.
  """

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)
    create_changeset = Keyword.get(opts, :create_changeset, :changeset)
    update_changeset = Keyword.get(opts, :update_changeset, :changeset)

    quote do
      import Ecto.Query

      alias Sca.PublicId
      alias Sca.Repo

      @model unquote(model)

      @doc "Inserts a new record through the model's changeset."
      @spec create(map()) :: {:ok, unquote(model).t()} | {:error, Ecto.Changeset.t()}
      def create(attrs) do
        %unquote(model){}
        |> unquote(model).unquote(create_changeset)(attrs)
        |> Repo.insert()
      end

      @doc "Updates a record through the model's changeset."
      @spec update(unquote(model).t(), map()) ::
              {:ok, unquote(model).t()} | {:error, Ecto.Changeset.t()}
      def update(record, attrs) do
        record
        |> unquote(model).unquote(update_changeset)(attrs)
        |> Repo.update()
      end

      @doc """
      Writes fields straight to the row, bypassing validation.

      For state the schema does not validate — timestamps, counters, tokens the
      action has already checked.
      """
      @spec change(unquote(model).t(), keyword()) ::
              {:ok, unquote(model).t()} | {:error, Ecto.Changeset.t()}
      def change(record, fields) do
        record
        |> Ecto.Changeset.change(fields)
        |> Repo.update()
      end

      @doc "Fetches by primary key."
      @spec get(Ecto.UUID.t()) :: {:ok, unquote(model).t()} | {:error, :not_found}
      def get(id), do: wrap(Repo.get(@model, id))

      @doc "Fetches by primary key, raising when there is no such row."
      @spec get!(Ecto.UUID.t()) :: unquote(model).t()
      def get!(id), do: Repo.get!(@model, id)

      @doc "Fetches by the given clauses."
      @spec get_by(keyword()) :: {:ok, unquote(model).t()} | {:error, :not_found}
      def get_by(clauses), do: wrap(Repo.get_by(@model, clauses))

      @doc "Fetches by human-readable id, refusing ids that belong elsewhere."
      @spec get_by_public_id(String.t()) :: {:ok, unquote(model).t()} | {:error, :not_found}
      def get_by_public_id(public_id) do
        if PublicId.belongs_to?(public_id, @model) do
          wrap(Repo.get_by(@model, public_id: public_id))
        else
          {:error, :not_found}
        end
      end

      @doc """
      Fetches by the given clauses and holds the row until the surrounding
      transaction ends.

      For the read-check-write sequences that must not interleave: two devices
      scanning the same QR code, two decisions on the same request.
      """
      @spec lock_by(keyword()) :: {:ok, unquote(model).t()} | {:error, :not_found}
      def lock_by(clauses) do
        @model
        |> where(^clauses)
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> wrap()
      end

      @doc """
      Plain listing by equality clauses.

      `opts` takes `:order_by` (defaults to oldest first) and `:limit`. Anything
      that needs a real query — a comparison, a join — belongs in the repo
      itself, not in more options here.
      """
      @spec list_by(keyword(), keyword()) :: [unquote(model).t()]
      def list_by(clauses, opts \\ []) do
        @model
        |> where(^clauses)
        |> order_by(^Keyword.get(opts, :order_by, asc: :inserted_at))
        |> limit_to(Keyword.get(opts, :limit))
        |> Repo.all()
      end

      @doc """
      Paginated, filterable and sortable listing for the console screens.

      Returns `{records, %Flop.Meta{}}`; see the model's `Flop.Schema` for what
      can be filtered and sorted. Pass a query to scope it — a console list is
      always somebody's rows, never everybody's.
      """
      @spec list(map(), Ecto.Queryable.t()) :: {[unquote(model).t()], Flop.Meta.t()}
      def list(params \\ %{}, query \\ @model) do
        Flop.validate_and_run!(query, params, for: @model)
      end

      @doc "Every row, oldest first."
      @spec list_all() :: [unquote(model).t()]
      def list_all, do: list_by([])

      @spec delete(unquote(model).t()) ::
              {:ok, unquote(model).t()} | {:error, Ecto.Changeset.t()}
      def delete(record), do: Repo.delete(record)

      defp limit_to(query, nil), do: query
      defp limit_to(query, count), do: limit(query, ^count)

      defp wrap(nil), do: {:error, :not_found}
      defp wrap(record), do: {:ok, record}

      defoverridable create: 1, update: 2, change: 2, get: 1, get!: 1, get_by: 1, list: 1
    end
  end
end
