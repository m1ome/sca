defmodule Sca.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string, null: false, default: ""
      add :role, :string, null: false, default: "support"
      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admins, [:email])

    add_public_id(:admins, "ADM")
  end
end
