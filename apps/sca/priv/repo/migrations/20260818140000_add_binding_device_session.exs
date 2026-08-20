defmodule Sca.Repo.Migrations.AddBindingDeviceSession do
  use Ecto.Migration

  def change do
    alter table(:bindings) do
      # Handed out with the QR, signed into the device's key attestation.
      add :enroll_nonce, :string
      # Digest, not the token: the row is useless to whoever reads it.
      add :access_token_hash, :string
      add :access_token_expires_at, :utc_datetime_usec
      add :refresh_nonce, :string
    end

    create unique_index(:bindings, [:access_token_hash])
  end
end
