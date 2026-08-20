defmodule Sca.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :name, :string, null: false, default: ""
      add :password_hash, :string
      add :role, :string, null: false, default: "viewer"
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:users, [:tenant_id])
    create unique_index(:users, [:tenant_id, :email])

    add_public_id(:users, "USR")
  end
end
