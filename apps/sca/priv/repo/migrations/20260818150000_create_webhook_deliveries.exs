defmodule Sca.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :event, :string, null: false
      # A loose reference: a delivery outlives what it describes.
      add :resource_type, :string
      add :resource_id, :binary_id

      add :url, :string, null: false
      # Plaintext, even when the wire copy went out encrypted.
      add :payload, :map, null: false, default: "{}"
      add :encrypted, :boolean, null: false, default: false

      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :response_status, :integer
      add :response_body, :text
      add :error, :text
      add :duration_ms, :integer
      add :last_attempt_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhook_deliveries, [:tenant_id])
    create index(:webhook_deliveries, [:status])
    create index(:webhook_deliveries, [:resource_type, :resource_id])

    add_public_id(:webhook_deliveries, "WHK")
  end
end
