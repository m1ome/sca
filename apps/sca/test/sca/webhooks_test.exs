defmodule Sca.WebhooksTest do
  @moduledoc """
  `EmitWebhook` → `DeliverWebhook` → `RetryWebhook`, and what the merchant
  actually receives.
  """

  use Sca.DataCase, async: true

  import Ecto.Query
  import Mox

  alias Sca.Actions
  alias Sca.Models
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Webhooks
  alias Sca.Webhooks.ClientMock
  alias Sca.Webhooks.Envelope
  alias Sca.Webhooks.Sender
  alias Sca.Workers.WebhookDeliveryWorker

  setup :verify_on_exit!

  setup do
    tenant = insert(:tenant)

    %{tenant: tenant, device: Device.bind(tenant)}
  end

  defp payment_attrs do
    %{
      type: :payment,
      title: "Payment confirmation",
      payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
    }
  end

  describe "emit/2" do
    test "takes an event and the thing it happened to", %{tenant: tenant, device: device} do
      assert {:ok, delivery} = Webhooks.emit("binding.revoked", device.binding)

      assert delivery.event == "binding.revoked"
      assert delivery.resource_type == :binding
      assert delivery.resource_id == device.binding.id
      assert delivery.tenant_id == tenant.id
      assert delivery.url == tenant.settings.webhook_url
      assert delivery.payload["binding"]["id"] == device.binding.public_id
      assert_enqueued(worker: WebhookDeliveryWorker, args: %{delivery_id: delivery.id})
    end

    test "a request drags its binding into the payload without being asked", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert {:ok, delivery} = Webhooks.emit("request.expired", request)

      assert delivery.payload["request"]["id"] == request.public_id
      assert delivery.payload["binding"]["id"] == ctx.device.binding.public_id
    end

    test "a tenant with no endpoint is a normal answer, not an error" do
      tenant = insert(:tenant, settings: build(:settings, webhook_url: nil))
      device = Device.bind(tenant)
      queued = length(all_enqueued())

      assert Webhooks.emit("binding.revoked", device.binding) == {:ok, :no_endpoint}
      assert WebhookDeliveryRepo.list_by_tenant(tenant) == []
      assert length(all_enqueued()) == queued
    end
  end

  describe "emission" do
    test "binding.activated is queued when a device binds", %{tenant: tenant} do
      assert [delivery] = WebhookDeliveryRepo.list_by_tenant(tenant)

      assert delivery.event == "binding.activated"
      assert delivery.resource_type == :binding
      assert delivery.url == tenant.settings.webhook_url
      assert delivery.status == :pending
      assert delivery.payload["binding"]["status"] == "active"
      assert_enqueued(worker: WebhookDeliveryWorker, args: %{delivery_id: delivery.id})
    end

    test "a request is announced when created and when decided", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      {:ok, _decided} =
        Actions.Request.decide(
          request,
          ctx.device.binding,
          "confirm",
          Device.decide(ctx.device, request, "confirm")
        )

      events = ctx.tenant |> WebhookDeliveryRepo.list_by_tenant() |> Enum.map(& &1.event)

      assert "request.created" in events
      assert "request.confirmed" in events

      [confirmed] =
        Enum.filter(WebhookDeliveryRepo.list_for(request), &(&1.event == "request.confirmed"))

      assert confirmed.payload["request"]["signature"]
      assert confirmed.payload["request"]["signed_payload"]
      assert confirmed.payload["binding"]["id"] == ctx.device.binding.public_id
    end

    test "expiry and cancellation are announced too", ctx do
      {:ok, overdue} =
        Actions.Request.create(
          ctx.device.binding,
          Map.put(payment_attrs(), :expires_at, Timex.shift(Timex.now(), seconds: -1))
        )

      {:ok, live} = Actions.Request.create(ctx.device.binding, payment_attrs())

      Actions.Request.expire_overdue()
      {:ok, _cancelled} = Actions.Request.cancel(live)

      events = ctx.tenant |> WebhookDeliveryRepo.list_by_tenant() |> Enum.map(& &1.event)

      assert "request.expired" in events
      assert "request.cancelled" in events
      assert Enum.any?(WebhookDeliveryRepo.list_for(overdue), &(&1.event == "request.expired"))
    end

    test "a revoked binding is announced, lockout included", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      for _attempt <- 1..Models.Binding.max_failed_attempts() do
        binding = BindingRepo.get!(ctx.device.binding.id)
        Actions.Request.decide(request, binding, "confirm", "bad")
      end

      assert ctx.tenant
             |> WebhookDeliveryRepo.list_by_tenant()
             |> Enum.map(& &1.event)
             |> Enum.member?("binding.revoked")
    end

    test "a tenant without a webhook url gets no deliveries and no jobs" do
      tenant = insert(:tenant, settings: build(:settings, webhook_url: nil))
      device = Device.bind(tenant)

      assert WebhookDeliveryRepo.list_by_tenant(tenant) == []
      assert {:ok, _request} = Actions.Request.create(device.binding, payment_attrs())
      assert WebhookDeliveryRepo.list_by_tenant(tenant) == []
    end

    test "the delivery records whether the wire copy was encrypted", %{tenant: tenant} do
      {:ok, tenant} =
        Actions.Tenant.update_settings(tenant, %{webhook_certificate: certificate()})

      _device = Device.bind(tenant, %{external_id: "customer-encrypted"})

      assert [delivery | _rest] =
               tenant |> WebhookDeliveryRepo.list_by_tenant() |> Enum.filter(& &1.encrypted)

      assert delivery.event == "binding.activated"
      # So support can still answer "what did we send".
      assert delivery.payload["binding"]["status"] == "active"
    end
  end

  describe "Sender.deliver/3" do
    setup %{tenant: tenant} do
      %{delivery: hd(WebhookDeliveryRepo.list_by_tenant(tenant))}
    end

    test "a 2xx settles the delivery", %{delivery: delivery} do
      expect(ClientMock, :post, fn url, body, headers ->
        assert url == delivery.url
        assert %{"event" => "binding.activated"} = Jason.decode!(body)
        assert {"content-type", "application/json"} in headers

        {:ok, %{status: 200, body: "ok"}}
      end)

      assert Sender.deliver(delivery, 1, 8) == :ok

      delivery = WebhookDeliveryRepo.get!(delivery.id)
      assert delivery.status == :delivered
      assert delivery.response_status == 200
      assert delivery.response_body == "ok"
      assert delivery.attempts == 1
      assert delivery.delivered_at
      assert delivery.duration_ms >= 0
    end

    test "a 5xx keeps the delivery open for the next attempt", %{delivery: delivery} do
      expect(ClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{status: 503, body: "upstream down"}}
      end)

      assert {:error, "http 503"} = Sender.deliver(delivery, 1, 8)

      delivery = WebhookDeliveryRepo.get!(delivery.id)
      assert delivery.status == :pending
      assert delivery.response_status == 503
      assert delivery.response_body == "upstream down"
    end

    test "the last attempt closes the delivery as failed", %{delivery: delivery} do
      expect(ClientMock, :post, fn _url, _body, _headers -> {:error, :timeout} end)

      assert {:error, _reason} = Sender.deliver(delivery, 8, 8)

      delivery = WebhookDeliveryRepo.get!(delivery.id)
      assert delivery.status == :failed
      assert delivery.error =~ "timeout"
      assert delivery.attempts == 8
    end

    test "a huge error page is truncated, not stored whole", %{delivery: delivery} do
      expect(ClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{status: 500, body: String.duplicate("x", 10_000)}}
      end)

      Sender.deliver(delivery, 1, 8)

      assert byte_size(WebhookDeliveryRepo.get!(delivery.id).response_body) < 2_100
    end

    test "a certificate we cannot encrypt for cancels the job instead of retrying", ctx do
      # Straight through the repo: the action refuses such a PEM, so this is
      # the one that stopped being readable after it was accepted.
      {:ok, tenant} =
        TenantRepo.update(ctx.tenant, %{
          settings: %{
            webhook_url: ctx.tenant.settings.webhook_url,
            webhook_certificate: "-----BEGIN CERTIFICATE-----\ngarbage\n-----END CERTIFICATE-----"
          }
        })

      delivery = hd(WebhookDeliveryRepo.list_by_tenant(tenant))

      assert {:cancel, _reason} = Sender.deliver(delivery, 1, 8)
      assert WebhookDeliveryRepo.get!(delivery.id).status == :failed
    end
  end

  describe "the worker" do
    setup %{tenant: tenant} do
      %{delivery: hd(WebhookDeliveryRepo.list_by_tenant(tenant))}
    end

    test "delivers the queued webhook", %{delivery: delivery} do
      expect(ClientMock, :post, fn _url, _body, _headers -> {:ok, %{status: 204, body: ""}} end)

      assert :ok = perform_job(WebhookDeliveryWorker, %{delivery_id: delivery.id})
      assert WebhookDeliveryRepo.get!(delivery.id).status == :delivered
    end

    test "does nothing for a delivery that is already through", %{delivery: delivery} do
      expect(ClientMock, :post, fn _url, _body, _headers -> {:ok, %{status: 200, body: ""}} end)
      assert :ok = perform_job(WebhookDeliveryWorker, %{delivery_id: delivery.id})

      # A retry after a timeout that actually landed.
      assert :ok = perform_job(WebhookDeliveryWorker, %{delivery_id: delivery.id})
    end

    test "shrugs off a delivery that no longer exists" do
      assert :ok = perform_job(WebhookDeliveryWorker, %{delivery_id: Ecto.UUID.generate()})
    end

    test "backs off further with every attempt, with jitter" do
      # Past the cap only the jitter is left, so ordering stops holding.
      backoffs =
        for attempt <- 1..7 do
          WebhookDeliveryWorker.backoff(%Oban.Job{attempt: attempt, max_attempts: 8})
        end

      assert backoffs == Enum.sort(backoffs)
      assert List.first(backoffs) in 30..36

      capped = WebhookDeliveryWorker.backoff(%Oban.Job{attempt: 12, max_attempts: 12})
      assert capped in 3600..4320

      # Two jobs failing together must not come back together.
      spread =
        for _try <- 1..20 do
          WebhookDeliveryWorker.backoff(%Oban.Job{attempt: 5, max_attempts: 8})
        end

      assert length(Enum.uniq(spread)) > 1
    end
  end

  describe "retry/1" do
    test "deduplicates while a job is in flight, but not a deliberate resend", %{tenant: tenant} do
      delivery = hd(WebhookDeliveryRepo.list_by_tenant(tenant))

      # The queued job is still waiting, so this retry is a duplicate and says so.
      assert {:error, :already_queued} = Webhooks.retry(delivery)
      assert waiting_jobs() == 1

      # Once it has run, asking again is a resend and has to reach the queue.
      finish_jobs()

      assert {:ok, _delivery} = Webhooks.retry(delivery)
      assert waiting_jobs() == 1
    end

    test "reopens a failed delivery and queues it again", %{tenant: tenant} do
      delivery = hd(WebhookDeliveryRepo.list_by_tenant(tenant))
      expect(ClientMock, :post, fn _url, _body, _headers -> {:error, :nxdomain} end)
      Sender.deliver(delivery, 8, 8)
      finish_jobs()

      assert {:ok, reopened} = Webhooks.retry(WebhookDeliveryRepo.get!(delivery.id))
      assert reopened.status == :pending
      assert_enqueued(worker: WebhookDeliveryWorker, args: %{delivery_id: delivery.id})
    end
  end

  describe "the envelope" do
    test "signs the body with the tenant's secret", %{tenant: tenant} do
      delivery = hd(WebhookDeliveryRepo.list_by_tenant(tenant))
      now = Timex.now()

      {:ok, body, headers} =
        Envelope.build(Repo.preload(delivery, :tenant), tenant, now)

      signature = :proplists.get_value("x-sca-signature", headers)

      assert signature == Envelope.signature(tenant.settings.webhook_secret, body, now)
      assert signature =~ ~r/\At=\d+,v1=[0-9a-f]{64}\z/

      # The timestamp is inside the signed string, so a captured call cannot be
      # replayed under a later one.
      later = Timex.shift(now, seconds: 60)
      refute signature == Envelope.signature(tenant.settings.webhook_secret, body, later)
    end

    test "a tenant without a signing secret still gets a well-formed call", %{tenant: tenant} do
      {:ok, tenant} = TenantRepo.update(tenant, %{settings: %{webhook_secret: nil}})
      delivery = tenant |> WebhookDeliveryRepo.list_by_tenant() |> hd() |> Repo.preload(:tenant)

      {:ok, body, headers} = Envelope.build(delivery, tenant)

      # No secret, no signature header — but the call still goes out, and the
      # merchant can still route it.
      assert :proplists.get_value("x-sca-signature", headers) == :undefined
      assert {"x-sca-event", "binding.activated"} in headers
      assert Jason.decode!(body)["event"] == "binding.activated"
    end

    test "routing metadata stays readable when the body is encrypted", %{tenant: tenant} do
      {:ok, tenant} =
        Actions.Tenant.update_settings(tenant, %{webhook_certificate: certificate()})

      device = Device.bind(tenant, %{external_id: "customer-encrypted"})
      {:ok, request} = Actions.Request.create(device.binding, payment_attrs())

      delivery =
        request
        |> WebhookDeliveryRepo.list_for()
        |> hd()
        |> Repo.preload(:tenant)

      {:ok, body, headers} = Envelope.build(delivery, tenant)
      decoded = Jason.decode!(body)

      assert decoded["event"] == "request.created"
      assert decoded["id"] == delivery.public_id
      assert decoded["data"] == nil
      assert length(String.split(decoded["encrypted"], ".")) == 5

      assert decoded["encrypted"]
             |> String.split(".")
             |> hd()
             |> Base.url_decode64!(padding: false)
             |> Jason.decode!() == %{"alg" => "RSA-OAEP-256", "enc" => "A256GCM"}

      assert {"x-sca-event", "request.created"} in headers
    end
  end

  test "deliveries can be listed by status", %{tenant: tenant} do
    delivery = hd(WebhookDeliveryRepo.list_by_tenant(tenant))
    expect(ClientMock, :post, fn _url, _body, _headers -> {:ok, %{status: 200, body: ""}} end)
    Sender.deliver(delivery, 1, 8)

    assert [%Models.WebhookDelivery{status: :delivered}] =
             WebhookDeliveryRepo.list_by_tenant(tenant, status: :delivered)

    assert WebhookDeliveryRepo.list_by_tenant(tenant, status: :failed) == []
  end

  defp waiting_jobs do
    Repo.aggregate(from(job in Oban.Job, where: job.state == "available"), :count)
  end

  defp finish_jobs do
    Repo.update_all(Oban.Job, set: [state: "completed", completed_at: Timex.now()])
  end

  defp certificate do
    "../support/fixtures/webhook_cert.pem" |> Path.expand(__DIR__) |> File.read!()
  end
end
