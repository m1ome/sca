defmodule Sca.Repo.Migrations.CreateBindings do
  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      # Unique per tenant, so re-enrolling replaces the binding instead of
      # leaving a dead one behind.
      add :external_id, :string, null: false
      add :name, :string, null: false, default: ""
      add :status, :string, null: false, default: "pending"

      # The token encoded into the QR code.
      add :enroll_token, :string
      add :enroll_expires_at, :utc_datetime_usec

      add :public_key, :text
      add :algorithm, :string, null: false, default: "ecdsa-p256"
      add :device_info, :map, null: false, default: "{}"
      add :attested, :boolean, null: false, default: false
      add :attestation_type, :string
      add :attestation_level, :string

      add :push_token, :string
      add :push_platform, :string

      # PSD2 RTS Art 4(3)(b): lock the device after repeated failures.
      add :failed_attempts, :integer, null: false, default: 0

      add :activated_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bindings, [:tenant_id])
    create unique_index(:bindings, [:tenant_id, :external_id])
    create unique_index(:bindings, [:enroll_token])

    add_public_id(:bindings, "BIN")
  end
end
