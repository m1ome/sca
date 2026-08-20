defmodule Sca.Scope do
  @moduledoc """
  Who is asking, and what they are allowed to see.

  Actions take entities and trust that the caller had the right to them. That
  trust has to end somewhere, and it ends here: an HTTP layer resolves ids
  through a scope, never through a bare repository lookup.

      scope = Scope.for_tenant(tenant)

      with {:ok, binding} <- Scope.fetch_binding(scope, params["binding_id"]),
           {:ok, request} <- Actions.Request.create(binding, params) do
        ...
      end

  Anything belonging to another tenant answers `:not_found`, not `:forbidden` —
  confirming that `BIN-91` exists somewhere is already more than a stranger
  should learn.
  """

  alias Sca.Models
  alias Sca.Repos.ApiTokenRepo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Repos.UserRepo
  alias Sca.Repos.WebhookDeliveryRepo

  @enforce_keys [:tenant]
  defstruct [:tenant]

  @type t() :: %__MODULE__{tenant: Models.Tenant.t()}

  @doc "A scope for everything one merchant may touch."
  @spec for_tenant(Models.Tenant.t()) :: t()
  def for_tenant(%Models.Tenant{} = tenant), do: %__MODULE__{tenant: tenant}

  @doc "Whether the entity belongs to this scope's tenant."
  @spec owns?(t(), struct()) :: boolean()
  def owns?(%__MODULE__{tenant: tenant}, %{tenant_id: tenant_id}), do: tenant.id == tenant_id
  def owns?(%__MODULE__{}, _entity), do: false

  @doc "Looks a binding up by its public id, inside the scope."
  @spec fetch_binding(t(), String.t()) :: {:ok, Models.Binding.t()} | {:error, :not_found}
  def fetch_binding(scope, public_id), do: scoped(scope, BindingRepo.get_by_public_id(public_id))

  @doc "Looks a binding up by the merchant's own identifier."
  @spec fetch_binding_by_external_id(t(), String.t()) ::
          {:ok, Models.Binding.t()} | {:error, :not_found}
  def fetch_binding_by_external_id(%__MODULE__{tenant: tenant}, external_id) do
    BindingRepo.get_by_external_id(tenant, external_id)
  end

  @doc "Looks a request up by its public id, inside the scope."
  @spec fetch_request(t(), String.t()) :: {:ok, Models.Request.t()} | {:error, :not_found}
  def fetch_request(scope, public_id), do: scoped(scope, RequestRepo.get_by_public_id(public_id))

  @doc "Looks a request up by the merchant's idempotency key."
  @spec fetch_request_by_external_id(t(), String.t()) ::
          {:ok, Models.Request.t()} | {:error, :not_found}
  def fetch_request_by_external_id(%__MODULE__{tenant: tenant}, external_id) do
    RequestRepo.get_by_external_id(tenant, external_id)
  end

  @doc "Looks a team member up by their public id, inside the scope."
  @spec fetch_user(t(), String.t()) :: {:ok, Models.User.t()} | {:error, :not_found}
  def fetch_user(scope, public_id), do: scoped(scope, UserRepo.get_by_public_id(public_id))

  @doc "Looks an API key up by its public id, inside the scope."
  @spec fetch_api_token(t(), String.t()) :: {:ok, Models.ApiToken.t()} | {:error, :not_found}
  def fetch_api_token(scope, public_id),
    do: scoped(scope, ApiTokenRepo.get_by_public_id(public_id))

  @doc "Looks a webhook delivery up by its public id, inside the scope."
  @spec fetch_delivery(t(), String.t()) ::
          {:ok, Models.WebhookDelivery.t()} | {:error, :not_found}
  def fetch_delivery(scope, public_id) do
    scoped(scope, WebhookDeliveryRepo.get_by_public_id(public_id))
  end

  defp scoped(scope, {:ok, entity}) do
    if owns?(scope, entity), do: {:ok, entity}, else: {:error, :not_found}
  end

  defp scoped(_scope, {:error, :not_found}), do: {:error, :not_found}
end
