defmodule Sca.Release do
  @moduledoc """
  Tasks a release has no `mix` to run: `bin/sca eval "Sca.Release.migrate()"`.
  """

  @app :sca

  @doc "Runs every pending migration."
  def migrate do
    load()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls one repo back to the given version."
  def rollback(repo, version) do
    load()

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Load, not start: `with_repo` brings the repo up on its own, and a migration
  # step has no business starting endpoints and Oban.
  defp load, do: Application.load(@app)
end
