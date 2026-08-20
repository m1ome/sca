defmodule Sca.Release do
  @moduledoc """
  Tasks a release has no `mix` to run: `bin/sca eval "Sca.Release.migrate()"`.

  The overlays in `rel/overlays/bin` wrap them, so a deployment runs
  `/app/bin/setup` (schema plus the first staff account) or `/app/bin/migrate`.
  """

  require Logger

  alias Sca.Actions
  alias Sca.Repos.AdminRepo

  @app :sca

  @doc """
  Brings an environment up to date: migrations, then the first staff account.

  Safe on every deploy — both halves do nothing when there is nothing to do.
  """
  def setup do
    migrate()
    bootstrap_admin()
  end

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

  @doc """
  Creates the first staff account from `ADMIN_EMAIL` and `ADMIN_PASSWORD`.

  A console nobody can sign into is a dead end, and there is no sign-up: the
  first account has to come from somewhere outside the product. It is created
  once — the moment any admin exists this does nothing, so the variables can
  stay set and the command can stay in the deploy.

  Refusing loudly when the variables are set but the account cannot be created
  is deliberate: a silent skip leaves someone believing they have a login.
  """
  def bootstrap_admin do
    load()

    {:ok, result, _apps} = Ecto.Migrator.with_repo(Sca.Repo, fn _repo -> create_first_admin() end)

    result
  end

  @doc false
  def create_first_admin do
    email = System.get_env("ADMIN_EMAIL")
    password = System.get_env("ADMIN_PASSWORD")

    cond do
      AdminRepo.list_all() != [] -> :ok
      is_nil(email) or is_nil(password) -> missing_credentials()
      true -> create_admin(email, password)
    end
  end

  defp missing_credentials do
    Logger.info("[release.bootstrap_admin] ADMIN_EMAIL and ADMIN_PASSWORD are not set; skipping")

    :ok
  end

  defp create_admin(email, password) do
    attrs = %{email: email, password: password, role: :superadmin, name: "Owner"}

    case Actions.Admin.create(attrs) do
      {:ok, %{admin: admin}} ->
        Logger.info("[release.bootstrap_admin] #{admin.public_id} created for #{admin.email}")

        :ok

      {:error, changeset} ->
        raise """
        ADMIN_EMAIL and ADMIN_PASSWORD are set, but no account could be made of them:
        #{inspect(Sca.Errors.to_map(changeset))}
        """
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Load, not start: `with_repo` brings the repo up on its own, and a migration
  # step has no business starting endpoints and Oban.
  defp load, do: Application.load(@app)
end
