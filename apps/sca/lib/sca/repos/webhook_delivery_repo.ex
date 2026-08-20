defmodule Sca.Repos.WebhookDeliveryRepo do
  @moduledoc """
  Persistence for webhook deliveries — the record of what we told a merchant
  and what they answered.
  """

  use Sca.Repo.Base, model: Sca.Models.WebhookDelivery

  alias Sca.Models.Binding
  alias Sca.Models.Request
  alias Sca.Models.Tenant
  alias Sca.Models.WebhookDelivery

  @spec record_attempt(WebhookDelivery.t(), map()) ::
          {:ok, WebhookDelivery.t()} | {:error, Ecto.Changeset.t()}
  def record_attempt(%WebhookDelivery{} = delivery, attrs) do
    delivery
    |> WebhookDelivery.attempt_changeset(attrs)
    |> Repo.update()
  end

  @doc "A page of one merchant's deliveries, for the console."
  @spec page_for_tenant(Tenant.t(), map()) :: {[WebhookDelivery.t()], Flop.Meta.t()}
  def page_for_tenant(%Tenant{id: tenant_id}, params) do
    list(params, where(WebhookDelivery, tenant_id: ^tenant_id))
  end

  @spec list_by_tenant(Tenant.t(), keyword()) :: [WebhookDelivery.t()]
  def list_by_tenant(%Tenant{id: tenant_id}, opts \\ []) do
    clauses = [tenant_id: tenant_id] ++ Keyword.take(opts, [:status])

    list_by(clauses, order_by: [desc: :inserted_at], limit: Keyword.get(opts, :limit, 100))
  end

  @doc "Deliveries describing one request or binding, newest first."
  @spec list_for(Request.t() | Binding.t()) :: [WebhookDelivery.t()]
  def list_for(%Request{id: id}), do: list_for_resource(:request, id)
  def list_for(%Binding{id: id}), do: list_for_resource(:binding, id)

  defp list_for_resource(type, id) do
    list_by([resource_type: type, resource_id: id], order_by: [desc: :inserted_at])
  end
end
