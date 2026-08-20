defmodule Sca.Repo.Migrations.AddIdempotencyKeys do
  use Ecto.Migration

  def change do
    # Only bindings: a request already carries the merchant's own reference,
    # unique per tenant, and that is the same thing. A binding's `external_id`
    # names a person instead — re-enrolling it deliberately replaces their
    # device — so retry-safety there needs a key of its own.
    alter table(:bindings) do
      add :idempotency_key, :string
    end

    create unique_index(:bindings, [:tenant_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL"
           )
  end
end
