defmodule Sca.Repo.Migrations.AddWebhookDeliveryTest do
  use Ecto.Migration

  def change do
    # A delivery a merchant asked for from the console, about nothing that
    # happened: it has to be told apart from the real traffic beside it.
    alter table(:webhook_deliveries) do
      add :test, :boolean, null: false, default: false
    end
  end
end
