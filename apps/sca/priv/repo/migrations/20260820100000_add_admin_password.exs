defmodule Sca.Repo.Migrations.AddAdminPassword do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :password_hash, :string
    end
  end
end
