defmodule Sca.Actions.Tenant do
  @moduledoc """
  Everything that happens to a merchant's tenant: onboarding it, turning it off,
  changing its settings and managing the team inside it.
  """

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Repo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo
  alias Sca.Webhooks.Encryption

  @type onboarding() :: %{
          tenant: Models.Tenant.t(),
          user: Models.User.t(),
          password: String.t()
        }

  @doc """
  Onboards a merchant: the tenant and its first team member in one transaction.

  A tenant nobody can sign into is a dead end, so the owner is created here with
  a generated password, returned once and never stored. The webhook signing
  secret is born with the tenant: opt-in would leave the default insecure.

      Tenant.create(%{name: "ACME Bank", owner_email: "ops@acme.example.com"})
  """
  @spec create(map()) :: {:ok, onboarding()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    attrs = stringify(attrs)
    password = Crypto.random_token(12)

    Repo.transact(fn ->
      with {:ok, tenant} <- TenantRepo.create(tenant_attrs(attrs)),
           {:ok, user} <- UserRepo.create(owner_attrs(attrs, tenant, password)) do
        Logger.info("[actions.tenant.create] #{tenant.public_id} with owner #{user.public_id}")

        {:ok, %{tenant: tenant, user: user, password: password}}
      else
        {:error, error} ->
          Logger.warning("[actions.tenant.create] rejected: #{reason(error)}")

          {:error, error}
      end
    end)
  end

  @doc """
  Turns a tenant off. Nothing is deleted and no device is touched — the tenant
  simply stops being served.
  """
  @spec deactivate(Models.Tenant.t()) :: {:ok, Models.Tenant.t()} | {:error, Ecto.Changeset.t()}
  def deactivate(%Models.Tenant{} = tenant) do
    case TenantRepo.update(tenant, %{status: :suspended}) do
      {:ok, tenant} ->
        Logger.info("[actions.tenant.deactivate] #{tenant.public_id} suspended")

        {:ok, tenant}

      {:error, error} ->
        Logger.warning("[actions.tenant.deactivate] #{tenant.public_id} failed: #{reason(error)}")

        {:error, error}
    end
  end

  @spec activate(Models.Tenant.t()) :: {:ok, Models.Tenant.t()} | {:error, Ecto.Changeset.t()}
  def activate(%Models.Tenant{} = tenant) do
    case TenantRepo.update(tenant, %{status: :active}) do
      {:ok, tenant} ->
        Logger.info("[actions.tenant.activate] #{tenant.public_id} active again")

        {:ok, tenant}

      {:error, error} ->
        Logger.warning("[actions.tenant.activate] #{tenant.public_id} failed: #{reason(error)}")

        {:error, error}
    end
  end

  @doc """
  Updates the settings that were given, leaving the rest alone.

  The certificate is checked where someone pastes it, not at the first webhook:
  otherwise a bad PEM fails deliveries hours later, unseen.
  """
  @spec update_settings(Models.Tenant.t(), map()) ::
          {:ok, Models.Tenant.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(%Models.Tenant{} = tenant, attrs) do
    # Keys, never values: settings carry the signing secret and the certificate.
    changed = attrs |> Map.keys() |> Enum.map_join(", ", &to_string/1)

    with :ok <- validate_certificate(attrs),
         {:ok, updated} <- TenantRepo.update(tenant, %{settings: attrs}) do
      Logger.info("[actions.tenant.update_settings] #{tenant.public_id} set #{changed}")

      {:ok, updated}
    else
      {:error, error} ->
        Logger.warning(
          "[actions.tenant.update_settings] #{tenant.public_id} rejected: #{reason(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Replaces the webhook signing secret. Queued deliveries read it when they are
  sent, so a rotation catches retries of older calls too.
  """
  @spec rotate_webhook_secret(Models.Tenant.t()) ::
          {:ok, Models.Tenant.t()} | {:error, Ecto.Changeset.t()}
  def rotate_webhook_secret(%Models.Tenant{} = tenant) do
    Logger.info("[actions.tenant.rotate_webhook_secret] #{tenant.public_id}")

    update_settings(tenant, %{webhook_secret: Crypto.random_token(32)})
  end

  @doc """
  Adds a member to the team, generating a password if none was given.

  The returned password is `nil` when the caller supplied one, and otherwise the
  only copy: an invitation has to carry it.
  """
  @spec add_user(Models.Tenant.t(), map()) ::
          {:ok, %{user: Models.User.t(), password: String.t() | nil}}
          | {:error, Ecto.Changeset.t()}
  def add_user(%Models.Tenant{} = tenant, attrs) do
    attrs = stringify(attrs)
    {password, generated} = password_for(attrs)

    member_attrs =
      attrs
      |> Map.put("tenant_id", tenant.id)
      |> Map.put("password", password)

    case UserRepo.create(member_attrs) do
      {:ok, user} ->
        Logger.info(
          "[actions.tenant.add_user] #{user.public_id} (#{user.role}) to #{tenant.public_id}"
        )

        {:ok, %{user: user, password: generated}}

      {:error, changeset} ->
        Logger.warning("[actions.tenant.add_user] rejected: #{reason(changeset)}")

        {:error, changeset}
    end
  end

  @doc """
  Changes what a member may do. Roles are not a ladder: an owner may demote
  themselves, and the console is what asks whether they meant it.
  """
  @spec change_user_role(Models.User.t(), atom() | String.t()) ::
          {:ok, Models.User.t()} | {:error, Ecto.Changeset.t()}
  def change_user_role(%Models.User{} = user, role) do
    case UserRepo.update(user, %{role: role}) do
      {:ok, user} ->
        Logger.info("[actions.tenant.change_user_role] #{user.public_id} is now #{user.role}")

        {:ok, user}

      {:error, error} ->
        Logger.warning("[actions.tenant.change_user_role] #{user.public_id}: #{reason(error)}")

        {:error, error}
    end
  end

  @doc """
  Gives a member a new password and hands it over once — a way back in that does
  not involve an owner inventing one for them.
  """
  @spec reset_user_password(Models.User.t()) ::
          {:ok, %{user: Models.User.t(), password: String.t()}} | {:error, Ecto.Changeset.t()}
  def reset_user_password(%Models.User{} = user) do
    password = Crypto.random_token(12)

    with {:ok, user} <- change_user_password(user, password) do
      {:ok, %{user: user, password: password}}
    end
  end

  @doc "Replaces a member's password."
  @spec change_user_password(Models.User.t(), String.t()) ::
          {:ok, Models.User.t()} | {:error, Ecto.Changeset.t()}
  def change_user_password(%Models.User{} = user, password) do
    case UserRepo.update_password(user, password) do
      {:ok, user} ->
        Logger.info("[actions.tenant.change_user_password] #{user.public_id}")

        {:ok, user}

      {:error, error} ->
        Logger.warning(
          "[actions.tenant.change_user_password] #{user.public_id} rejected: #{reason(error)}"
        )

        {:error, error}
    end
  end

  @doc "Takes a member out of the team without deleting their trail."
  @spec disable_user(Models.User.t()) :: {:ok, Models.User.t()} | {:error, Ecto.Changeset.t()}
  def disable_user(%Models.User{} = user), do: set_user_status(user, :disabled)

  @doc "Lets a member back in."
  @spec enable_user(Models.User.t()) :: {:ok, Models.User.t()} | {:error, Ecto.Changeset.t()}
  def enable_user(%Models.User{} = user), do: set_user_status(user, :active)

  defp set_user_status(user, status) do
    case UserRepo.update(user, %{status: status}) do
      {:ok, user} ->
        Logger.info("[actions.tenant.set_user_status] #{user.public_id} is #{user.status}")

        {:ok, user}

      {:error, error} ->
        Logger.warning("[actions.tenant.set_user_status] #{user.public_id}: #{reason(error)}")

        {:error, error}
    end
  end

  defp tenant_attrs(attrs) do
    settings =
      attrs
      |> Map.get("settings", %{})
      |> stringify()
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.put_new_lazy("webhook_secret", fn -> Crypto.random_token(32) end)

    attrs
    |> Map.take(["name", "status"])
    |> Map.put("settings", settings)
  end

  # The password, plus the copy we owe the caller — only if we made it up.
  defp password_for(%{"password" => password}) when is_binary(password) and password != "" do
    {password, nil}
  end

  defp password_for(_attrs) do
    generated = Crypto.random_token(12)

    {generated, generated}
  end

  defp owner_attrs(attrs, tenant, password) do
    %{
      "tenant_id" => tenant.id,
      "email" => Map.get(attrs, "owner_email"),
      "name" => Map.get(attrs, "owner_name", ""),
      "role" => :owner,
      "password" => password
    }
  end

  defp validate_certificate(attrs) do
    case attrs[:webhook_certificate] || attrs["webhook_certificate"] do
      blank when blank in [nil, ""] ->
        :ok

      certificate ->
        case Encryption.public_key_from_pem(certificate) do
          {:ok, _jwk} -> :ok
          {:error, reason} -> {:error, certificate_error(reason)}
        end
    end
  end

  defp certificate_error(reason) do
    %Models.Tenant{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:settings, "webhook_certificate #{message(reason)}")
  end

  defp message(:invalid_pem), do: "is not a readable PEM"
  defp message(:unsupported_certificate), do: "must carry an RSA public key"
end
