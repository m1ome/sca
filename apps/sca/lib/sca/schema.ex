defmodule Sca.Schema do
  @moduledoc """
  Base for every domain schema.

  Primary keys are UUIDs, so they stay opaque. Most entities also carry a
  `public_id` — `TNT-1`, `BIN-42` — from a Postgres sequence
  (`Sca.Repo.Migration.add_public_id/2`): that is what support and merchants
  quote at each other, while the UUID stays internal.

      defmodule Sca.Models.Tenant do
        use Sca.Schema, public_id: "TNT"

        schema "tenants" do
          public_id_field()
          field :name, :string
          timestamps()
        end
      end
  """

  defmacro __using__(opts) do
    prefix = Keyword.get(opts, :public_id)

    quote do
      use Ecto.Schema

      import Ecto.Changeset
      import Sca.Schema, only: [public_id_field: 0]

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]

      if unquote(prefix) do
        @doc "Prefix of this schema's human-readable identifier, e.g. `\"TNT\"`."
        def __public_id_prefix__, do: unquote(prefix)
      end
    end
  end

  @doc """
  Declares the `public_id` field inside a `schema` block.

  The value is filled in by the database default, so it is read back via
  `RETURNING` after insert.
  """
  defmacro public_id_field do
    quote do
      field :public_id, :string, read_after_writes: true
    end
  end
end
