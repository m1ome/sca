defmodule Sca.Repos.RequestRepo do
  @moduledoc """
  Persistence for approve/decline requests.
  """

  use Sca.Repo.Base, model: Sca.Models.Request

  alias Sca.Models.Binding
  alias Sca.Models.Request
  alias Sca.Models.Tenant

  @spec get_by_idempotency_key(Tenant.t(), String.t()) ::
          {:ok, Request.t()} | {:error, :not_found}
  def get_by_idempotency_key(%Tenant{id: tenant_id}, key) when is_binary(key) do
    get_by(tenant_id: tenant_id, idempotency_key: key)
  end

  @spec record_decision(Request.t(), Request.status(), map()) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def record_decision(%Request{} = request, status, attrs) do
    request
    |> Request.decision_changeset(status, attrs)
    |> Repo.update()
  end

  @doc "Finds a request by the merchant's idempotency key."
  @spec get_by_external_id(Tenant.t(), String.t()) :: {:ok, Request.t()} | {:error, :not_found}
  def get_by_external_id(%Tenant{id: tenant_id}, external_id) when is_binary(external_id) do
    get_by(tenant_id: tenant_id, external_id: external_id)
  end

  @doc "Locks a request for the length of the surrounding transaction."
  @spec lock(Ecto.UUID.t()) :: {:ok, Request.t()} | {:error, :not_found}
  def lock(id), do: lock_by(id: id)

  @spec list_by_binding(Binding.t()) :: [Request.t()]
  def list_by_binding(%Binding{id: binding_id}) do
    list_by([binding_id: binding_id], order_by: [desc: :inserted_at])
  end

  @spec list_by_tenant(Tenant.t()) :: [Request.t()]
  def list_by_tenant(%Tenant{id: tenant_id}) do
    list_by([tenant_id: tenant_id], order_by: [desc: :inserted_at])
  end

  @doc "A page of the tenant's requests, filtered and sorted by the console."
  @spec page_for_tenant(Tenant.t(), map()) :: {[Request.t()], Flop.Meta.t()}
  def page_for_tenant(%Tenant{id: tenant_id}, params) do
    list(params, where(Request, tenant_id: ^tenant_id))
  end

  @doc "A page of every merchant's requests, for the admin console."
  @spec page(map()) :: {[Request.t()], Flop.Meta.t()}
  def page(params), do: list(params)

  @spec list_pending(Binding.t()) :: [Request.t()]
  def list_pending(%Binding{id: binding_id}) do
    now = Timex.now()

    Request
    |> where([r], r.binding_id == ^binding_id and r.status == :pending and r.expires_at > ^now)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc "Marks every overdue request as expired and returns the rows it closed."
  @spec expire_overdue(DateTime.t()) :: [Request.t()]
  def expire_overdue(now) do
    {_count, expired} =
      Request
      |> where([r], r.status == :pending and r.expires_at <= ^now)
      |> select([r], r)
      |> Repo.update_all([set: [status: :expired, updated_at: now]], returning: true)

    expired || []
  end
end
