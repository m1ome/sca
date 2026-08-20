defmodule Sca.PushTest do
  @moduledoc """
  What lands on a phone, and what deliberately does not.

  The message shape is a contract with the mobile client: it reads `data.c` and
  `data.a` to open the right approval, on both platforms.
  """

  use Sca.DataCase, async: true

  import Mox

  alias Sca.Actions
  alias Sca.Push
  alias Sca.Push.ClientMock
  alias Sca.Push.Message
  alias Sca.Repos.BindingRepo
  alias Sca.Workers.PushWorker

  setup :verify_on_exit!

  setup do
    tenant = insert(:tenant)
    device = Device.bind(tenant)

    {:ok, binding} =
      BindingRepo.update(device.binding, %{push_token: "fcm-token", push_platform: :ios})

    %{tenant: tenant, binding: binding}
  end

  defp payment(binding) do
    {:ok, request} =
      Actions.Request.create(binding, %{
        type: :payment,
        title: "Payment confirmation",
        description: "Open the app to confirm",
        payload: %{"amount" => "149.90", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
      })

    request
  end

  describe "the message" do
    test "carries the deep link the client parses", ctx do
      request = payment(ctx.binding)

      %{"message" => message} = Message.build(request, ctx.binding)

      assert message["token"] == "fcm-token"
      assert message["data"] == %{"c" => ctx.binding.id, "a" => request.id, "x" => ""}
    end

    test "says the title and the description, and nothing that was signed", ctx do
      request = payment(ctx.binding)

      %{"message" => message} = Message.build(request, ctx.binding)
      body = Jason.encode!(message)

      assert message["notification"] == %{
               "title" => "Payment confirmation",
               "body" => "Open the app to confirm"
             }

      # A push passes through Google and Apple and lands on a lock screen.
      refute body =~ "149.90"
      refute body =~ "ACME Ltd"
      refute body =~ request.payload_hash
    end

    test "asks both platforms to deliver now and to stop when the request dies", ctx do
      request = payment(ctx.binding)

      %{"message" => message} = Message.build(request, ctx.binding)

      assert message["android"]["priority"] == "high"
      assert message["android"]["ttl"] =~ ~r/\A\d+s\z/
      assert message["apns"]["headers"]["apns-priority"] == "10"

      assert message["apns"]["headers"]["apns-expiration"] ==
               to_string(Timex.to_unix(request.expires_at))

      assert message["apns"]["payload"]["aps"]["category"] == "sca_auth_actions"
    end

    test "an already expired request carries no ttl at all", ctx do
      {:ok, overdue} =
        Actions.Request.create(ctx.binding, %{
          type: :freeform,
          title: "Late",
          expires_at: Timex.shift(Timex.now(), seconds: -1)
        })

      %{"message" => message} = Message.build(overdue, ctx.binding)

      refute Map.has_key?(message["android"], "ttl")
      refute Map.has_key?(message["apns"]["headers"], "apns-expiration")
    end
  end

  describe "queueing" do
    test "raising a request queues exactly one notification", ctx do
      request = payment(ctx.binding)

      assert_enqueued(
        worker: PushWorker,
        args: %{request_id: request.id, binding_id: ctx.binding.id}
      )
    end

    test "a device without a token is not an error", ctx do
      {:ok, silent} = BindingRepo.update(ctx.binding, %{push_token: nil})

      assert {:ok, :no_token} = Push.queue(payment(silent), silent)
    end
  end

  describe "the worker" do
    test "sends what the message builder produced", ctx do
      request = payment(ctx.binding)

      expect(ClientMock, :send, fn %{"message" => message} ->
        assert message["data"]["a"] == request.id
        :ok
      end)

      assert :ok = perform_job(PushWorker, %{request_id: request.id, binding_id: ctx.binding.id})
    end

    test "a failure is retried by Oban", ctx do
      request = payment(ctx.binding)
      expect(ClientMock, :send, fn _message -> {:error, "fcm 503"} end)

      assert {:error, "fcm 503"} =
               perform_job(PushWorker, %{request_id: request.id, binding_id: ctx.binding.id})
    end

    test "nothing is sent for a request that was already answered", ctx do
      request = payment(ctx.binding)
      {:ok, _cancelled} = Actions.Request.cancel(request)

      # No expectation on the mock: nothing should be sent.
      assert :ok = perform_job(PushWorker, %{request_id: request.id, binding_id: ctx.binding.id})
    end

    test "nothing is sent to a revoked device", ctx do
      request = payment(ctx.binding)
      {:ok, _binding} = Actions.Binding.revoke(ctx.binding)

      assert :ok = perform_job(PushWorker, %{request_id: request.id, binding_id: ctx.binding.id})
    end

    test "a deleted request is not a failure", ctx do
      assert :ok =
               perform_job(PushWorker, %{
                 request_id: Ecto.UUID.generate(),
                 binding_id: ctx.binding.id
               })
    end

    test "a token FCM no longer knows is dropped instead of retried", ctx do
      request = payment(ctx.binding)
      expect(ClientMock, :send, fn _message -> {:error, :unregistered} end)

      assert :ok = perform_job(PushWorker, %{request_id: request.id, binding_id: ctx.binding.id})

      {:ok, binding} = BindingRepo.get(ctx.binding.id)
      assert is_nil(binding.push_token)
    end

    test "backs off in seconds, not hours" do
      assert PushWorker.backoff(%Oban.Job{attempt: 1, max_attempts: 3}) == 10
      assert PushWorker.backoff(%Oban.Job{attempt: 3, max_attempts: 3}) == 30
    end
  end
end
