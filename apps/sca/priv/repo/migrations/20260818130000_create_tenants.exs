defmodule Sca.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      # jsonb: read as a whole, grows over time, never a query filter.
      add :settings, :map, null: false, default: "{}"

      timestamps(type: :utc_datetime_usec)
    end

    add_public_id(:tenants, "TNT")
  end
end
