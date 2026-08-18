defmodule Sca.Support.PublicIdMigration do
  @moduledoc """
  Throwaway table used by `Sca.Repo.MigrationTest` to exercise
  `Sca.Repo.Migration.add_public_id/2` end to end.
  """

  use Ecto.Migration

  import Sca.Repo.Migration

  def change do
    create table(:public_id_probes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime_usec)
    end

    add_public_id(:public_id_probes, "PRB")
  end
end
