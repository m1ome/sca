defmodule Sca.Repo.Migration do
  @moduledoc """
  Migration helpers shared by the domain.
  """

  import Ecto.Migration

  @prefix_format ~r/\A[A-Z][A-Z0-9]{0,7}\z/

  @doc """
  Adds a human-readable `public_id` column backed by its own sequence.

      create table(:tenants, primary_key: false) do
        add :id, :binary_id, primary_key: true
        timestamps(type: :utc_datetime_usec)
      end

      add_public_id(:tenants, "TN")

  Rows then get `TN-1`, `TN-2`, ... Numbering is done by Postgres, so
  concurrent inserts cannot collide and application code never has to know
  about the counter. The sequence is owned by the column, so dropping the
  table drops it too.

  Note that sequential identifiers are enumerable — `TN-137` tells anyone
  holding it how many tenants exist. If that ever matters, the suffix can be
  swapped for a random one without changing the `PREFIX-suffix` shape.
  """
  def add_public_id(table, prefix) when is_atom(table) or is_binary(table) do
    unless Regex.match?(@prefix_format, prefix) do
      raise ArgumentError,
            "public_id prefix must be uppercase alphanumeric, 1-8 chars, got: #{inspect(prefix)}"
    end

    sequence = "#{table}_public_id_seq"

    execute("CREATE SEQUENCE #{sequence}", "DROP SEQUENCE #{sequence}")

    alter table(table) do
      add :public_id, :string,
        null: false,
        default: fragment("'#{prefix}-' || nextval('#{sequence}')")
    end

    create unique_index(table, [:public_id])

    execute(
      "ALTER SEQUENCE #{sequence} OWNED BY #{table}.public_id",
      "ALTER SEQUENCE #{sequence} OWNED BY NONE"
    )
  end
end
