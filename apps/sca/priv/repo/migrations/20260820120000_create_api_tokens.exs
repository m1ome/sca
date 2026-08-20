defmodule Sca.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false, default: ""
      # The token is never stored: a digest to match, a preview to show.
      add :token_hash, :string, null: false
      add :preview, :string, null: false

      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:tenant_id])

    add_public_id(:api_tokens, "KEY")
  end
end
