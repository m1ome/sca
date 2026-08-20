defmodule Sca.Repo.Migrations.CreateRequests do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :binding_id, references(:bindings, type: :binary_id, on_delete: :delete_all),
        null: false

      # Merchant's idempotency key: a retried call must not raise a second card.
      add :external_id, :string

      add :type, :string, null: false
      add :title, :string, null: false
      add :description, :text, null: false, default: ""
      # The signed hash is order-independent, so key order carries no meaning.
      add :payload, :map, null: false, default: "{}"
      add :payload_hash, :string, null: false
      add :nonce, :string, null: false
      add :status, :string, null: false, default: "pending"

      add :signed_payload, :text
      add :signature, :text
      add :signature_algorithm, :string

      add :decided_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:requests, [:tenant_id])
    create index(:requests, [:binding_id])
    create index(:requests, [:status, :expires_at])
    create unique_index(:requests, [:tenant_id, :external_id], where: "external_id IS NOT NULL")

    add_public_id(:requests, "REQ")
  end
end
