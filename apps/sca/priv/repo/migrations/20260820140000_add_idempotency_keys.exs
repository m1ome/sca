defmodule Sca.Repo.Migrations.AddIdempotencyKeys do
  use Ecto.Migration

  def change do
    for table <- [:bindings, :requests] do
      alter table(table) do
        add :idempotency_key, :string
      end

      # Unique per merchant, and only where there is one: most rows are created
      # without a key and must not collide with each other.
      create unique_index(table, [:tenant_id, :idempotency_key],
               where: "idempotency_key IS NOT NULL"
             )
    end
  end
end
