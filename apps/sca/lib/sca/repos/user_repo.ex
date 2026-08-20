defmodule Sca.Repos.UserRepo do
  @moduledoc """
  Persistence for the merchant's team members.
  """

  use Sca.Repo.Base, model: Sca.Models.User, create_changeset: :registration_changeset

  alias Sca.Models.Tenant
  alias Sca.Models.User

  @spec update_password(User.t(), String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_password(%User{} = user, password) do
    user
    |> User.password_changeset(%{"password" => password})
    |> Repo.update()
  end

  @doc "Finds a team member by email inside their tenant, normalising the input."
  @spec get_by_email(Tenant.t(), String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_by_email(%Tenant{id: tenant_id}, email) when is_binary(email) do
    get_by(tenant_id: tenant_id, email: email |> String.trim() |> String.downcase())
  end

  @doc "A page of the merchant's team, filtered and sorted by the console."
  @spec page_for_tenant(Tenant.t(), map()) :: {[User.t()], Flop.Meta.t()}
  def page_for_tenant(%Tenant{id: tenant_id}, params) do
    list(params, where(User, tenant_id: ^tenant_id))
  end

  @spec list_by_tenant(Tenant.t()) :: [User.t()]
  def list_by_tenant(%Tenant{id: tenant_id}), do: list_by(tenant_id: tenant_id)
end
