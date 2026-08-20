defmodule Sca.Webhooks do
  @moduledoc """
  Outbound webhooks — the machinery, not a business operation.

  An action says what happened and hands over the thing it happened to:

      Webhooks.queue("request.created", request)   # inside the action's transaction
      Webhooks.emit("binding.revoked", binding)    # when there is no transaction open

  Everything else is this module's business: which tenant the entity belongs to,
  what the merchant sees (`Sca.Webhooks.Payload`), and handing the delivery to
  `Sca.Webhooks.Sender` through Oban.

  A tenant with no webhook URL resolves to `:no_endpoint` — a normal state, not
  an error, and it must not fail the action that produced the event.
  """

  require Logger

  alias Sca.Models
  alias Sca.Repo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Telemetry
  alias Sca.Webhooks.Payload
  alias Sca.Webhooks.Sender
  alias Sca.Workers.WebhookDeliveryWorker

  @events ~w(
    request.created request.confirmed request.declined request.expired request.cancelled
    binding.activated binding.revoked
  )

  @type queued() :: Models.WebhookDelivery.t() | :no_endpoint

  @doc "Events a merchant can receive."
  def events, do: @events

  @doc """
  Queues a webhook about `entity`, in its own transaction.

  Use `queue/2` when the entity is being written right now: the delivery then
  commits with it, so an event that was recorded is an event the merchant hears
  about, even if the node dies immediately after.
  """
  @spec emit(String.t(), struct()) :: {:ok, queued()} | {:error, term()}
  def emit(event, entity) when event in @events do
    Repo.transact(fn -> queue(event, entity) end)
  end

  @doc """
  Writes the delivery row and enqueues its job inside the caller's transaction.

  The primitive `emit/2` is built on; call it directly from an action that has
  already opened a transaction.
  """
  @spec queue(String.t(), struct()) :: {:ok, queued()} | {:error, term()}
  def queue(event, entity) when event in @events do
    with {:ok, tenant} <- TenantRepo.get(entity.tenant_id) do
      case tenant.settings.webhook_url do
        url when is_binary(url) and url != "" ->
          insert(tenant, event, entity, url)

        _missing ->
          Logger.debug("[webhooks] #{event} for #{tenant.public_id}: no endpoint configured")
          {:ok, :no_endpoint}
      end
    end
  end

  @doc """
  Queues another attempt for a delivery that failed or was never sent — the
  merchant fixed their endpoint and wants what they missed.
  """
  @spec retry(Models.WebhookDelivery.t()) ::
          {:ok, Models.WebhookDelivery.t()} | {:error, term()}
  def retry(%Models.WebhookDelivery{} = delivery) do
    Logger.info("[webhooks] retrying #{delivery.public_id} #{delivery.event}")

    with {:ok, delivery} <-
           WebhookDeliveryRepo.record_attempt(delivery, %{
             status: :pending,
             attempts: delivery.attempts
           }),
         {:ok, job} <- Oban.insert(WebhookDeliveryWorker.new(%{delivery_id: delivery.id})) do
      if job.conflict? do
        Logger.info("[webhooks] #{delivery.public_id} is already queued")

        {:error, :already_queued}
      else
        {:ok, delivery}
      end
    end
  end

  @doc """
  Sends one made-up event to the tenant's endpoint, right now.

  The merchant is standing in front of the console waiting for the answer, so
  this does not go through Oban: it posts on the caller's process, once, and
  hands back the delivery with whatever came back written on it. Everything else
  is a real delivery — the same envelope, the same signature, the same
  encryption — because a test that takes a shortcut proves nothing.

  A tenant with no endpoint is `{:error, :no_endpoint}`: here it *is* a refusal,
  unlike an event nobody asked for.
  """
  @spec send_test(Models.Tenant.t(), String.t()) ::
          {:ok, Models.WebhookDelivery.t()} | {:error, term()}
  def send_test(%Models.Tenant{} = tenant, event) when event in @events do
    case tenant.settings.webhook_url do
      url when is_binary(url) and url != "" ->
        deliver_test(tenant, event, url)

      _missing ->
        Logger.warning("[webhooks] test #{event} for #{tenant.public_id}: no endpoint configured")

        {:error, :no_endpoint}
    end
  end

  defp deliver_test(tenant, event, url) do
    with {:ok, delivery} <-
           WebhookDeliveryRepo.create(%{
             tenant_id: tenant.id,
             event: event,
             url: url,
             payload: Payload.sample(event),
             encrypted: is_binary(tenant.settings.webhook_certificate),
             test: true
           }) do
      Logger.info("[webhooks] testing #{delivery.public_id} #{event} for #{tenant.public_id}")
      Telemetry.emit([:webhook, :test], %{count: 1}, %{event: event, tenant_id: tenant.id})

      # One attempt of one: nobody wants a day of retries of a test.
      Sender.deliver(delivery, 1, 1)

      WebhookDeliveryRepo.get(delivery.id)
    end
  end

  defp insert(tenant, event, entity, url) do
    with {:ok, delivery} <-
           WebhookDeliveryRepo.create(%{
             tenant_id: tenant.id,
             event: event,
             resource_type: Payload.resource_type(entity),
             resource_id: entity.id,
             url: url,
             payload: Payload.build(entity),
             encrypted: is_binary(tenant.settings.webhook_certificate)
           }),
         {:ok, _job} <- Oban.insert(WebhookDeliveryWorker.new(%{delivery_id: delivery.id})) do
      Logger.info(
        "[webhooks] queued #{delivery.public_id} #{event} for #{tenant.public_id} → #{url}"
      )

      Telemetry.emit([:webhook, :queued], %{count: 1}, %{event: event, tenant_id: tenant.id})

      {:ok, delivery}
    end
  end
end
