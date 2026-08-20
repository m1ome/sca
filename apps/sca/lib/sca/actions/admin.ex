defmodule Sca.Actions.Admin do
  @moduledoc """
  Our own staff accounts.

  Separate from `Sca.Actions.Tenant` because an admin belongs to no merchant:
  they see every tenant, which is exactly why their account deserves its own
  module rather than a special case inside somebody else's.
  """

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Repos.AdminRepo

  @doc """
  Creates a staff account, generating a password unless one was given.

  The returned password is `nil` when the caller supplied their own, and
  otherwise the only copy — handing it over is the caller's business.
  """
  @spec create(map()) ::
          {:ok, %{admin: Models.Admin.t(), password: String.t() | nil}}
          | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    attrs = stringify(attrs)
    {password, generated} = password_for(attrs)

    case attrs |> Map.put("password", password) |> AdminRepo.create() do
      {:ok, admin} ->
        Logger.info("[actions.admin.create] #{admin.public_id} (#{admin.role})")

        {:ok, %{admin: admin, password: generated}}

      {:error, error} ->
        Logger.warning("[actions.admin.create] rejected: #{reason(error)}")

        {:error, error}
    end
  end

  defp password_for(%{"password" => password}) when is_binary(password) and password != "" do
    {password, nil}
  end

  defp password_for(_attrs) do
    generated = Crypto.random_token(12)

    {generated, generated}
  end

  @doc "Changes what a staff member may do."
  @spec change_role(Models.Admin.t(), atom() | String.t()) ::
          {:ok, Models.Admin.t()} | {:error, Ecto.Changeset.t()}
  def change_role(%Models.Admin{} = admin, role) do
    case AdminRepo.update(admin, %{role: role}) do
      {:ok, admin} ->
        Logger.info("[actions.admin.change_role] #{admin.public_id} is now #{admin.role}")

        {:ok, admin}

      {:error, error} ->
        Logger.warning("[actions.admin.change_role] #{admin.public_id}: #{reason(error)}")

        {:error, error}
    end
  end

  @doc "Replaces a staff member's password."
  @spec change_password(Models.Admin.t(), String.t()) ::
          {:ok, Models.Admin.t()} | {:error, Ecto.Changeset.t()}
  def change_password(%Models.Admin{} = admin, password) do
    case AdminRepo.update_password(admin, password) do
      {:ok, admin} ->
        Logger.info("[actions.admin.change_password] #{admin.public_id}")

        {:ok, admin}

      {:error, error} ->
        Logger.warning("[actions.admin.change_password] #{admin.public_id}: #{reason(error)}")

        {:error, error}
    end
  end

  @doc "Gives a staff member a new password and hands it over once."
  @spec reset_password(Models.Admin.t()) ::
          {:ok, %{admin: Models.Admin.t(), password: String.t()}} | {:error, Ecto.Changeset.t()}
  def reset_password(%Models.Admin{} = admin) do
    password = Crypto.random_token(12)

    with {:ok, admin} <- change_password(admin, password) do
      {:ok, %{admin: admin, password: password}}
    end
  end

  @doc "Takes a staff member out of the console without deleting their trail."
  @spec disable(Models.Admin.t()) :: {:ok, Models.Admin.t()} | {:error, Ecto.Changeset.t()}
  def disable(%Models.Admin{} = admin), do: set_status(admin, :disabled)

  @doc "Lets a staff member back in."
  @spec enable(Models.Admin.t()) :: {:ok, Models.Admin.t()} | {:error, Ecto.Changeset.t()}
  def enable(%Models.Admin{} = admin), do: set_status(admin, :active)

  @doc "Records that they just signed in."
  @spec track_login(Models.Admin.t()) :: {:ok, Models.Admin.t()} | {:error, Ecto.Changeset.t()}
  def track_login(%Models.Admin{} = admin), do: AdminRepo.track_login(admin)

  defp set_status(admin, status) do
    case AdminRepo.update(admin, %{status: status}) do
      {:ok, admin} ->
        Logger.info("[actions.admin.set_status] #{admin.public_id} is #{admin.status}")

        {:ok, admin}

      {:error, error} ->
        Logger.warning("[actions.admin.set_status] #{admin.public_id}: #{reason(error)}")

        {:error, error}
    end
  end
end
