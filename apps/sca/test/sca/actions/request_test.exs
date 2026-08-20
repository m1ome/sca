defmodule Sca.Actions.RequestTest do
  @moduledoc """
  `CreateRequest` → `DecideRequest`, plus `CancelRequest` and `ExpireRequests`:
  everything that decides whether a card can still be answered.
  """

  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo

  setup do
    tenant = insert(:tenant)

    %{tenant: tenant, device: Device.bind(tenant)}
  end

  defp payment_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        type: :payment,
        title: "Payment confirmation",
        description: "Transfer to ACME Ltd",
        payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
      },
      attrs
    )
  end

  describe "create_request/2" do
    test "fills in the tenant, the hash, a nonce and the deadline", ctx do
      assert {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert request.public_id =~ ~r/\AREQ-\d+\z/
      assert request.tenant_id == ctx.tenant.id
      assert request.binding_id == ctx.device.binding.id
      assert request.status == :pending
      assert is_binary(request.nonce)
      assert request.payload_hash == Crypto.payload_hash(request.payload)
      assert Timex.after?(request.expires_at, Timex.now())
    end

    test "normalises params the way the phone will render them", ctx do
      {:ok, request} =
        Actions.Request.create(
          ctx.device.binding,
          payment_attrs(%{
            payload: %{
              "amount" => "1 249,00",
              "currency" => "eur",
              "beneficiary" => "  ACME Ltd  ",
              "note" => ""
            }
          })
        )

      assert request.payload == %{
               "amount" => "1249.00",
               "currency" => "EUR",
               "beneficiary" => "ACME Ltd"
             }
    end

    test "refuses a payment without its required params", ctx do
      attrs = payment_attrs(%{payload: %{"amount" => "10.00"}})

      assert {:error, changeset} = Actions.Request.create(ctx.device.binding, attrs)
      assert %{payload: messages} = errors_on(changeset)
      assert Enum.count(messages, &(&1 == "is required for a payment request")) == 2
      assert %{"currency" => _, "beneficiary" => _} = Sca.Errors.to_map(changeset)
    end

    test "refuses params the device could not reproduce", ctx do
      attrs = payment_attrs(%{payload: %{"items" => %{"nested" => true}}})

      assert {:error, changeset} = Actions.Request.create(ctx.device.binding, attrs)
      assert %{payload: messages} = errors_on(changeset)
      assert Enum.any?(messages, &(&1 =~ "not signable"))
    end

    test "takes the deadline from the tenant's settings", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert_in_delta Timex.diff(request.expires_at, Timex.now(), :second), 300, 5
    end

    test "honours a tenant-specific timeout", ctx do
      {:ok, _tenant} =
        Actions.Tenant.update_settings(ctx.tenant, %{default_request_timeout_seconds: 60})

      binding = BindingRepo.get!(ctx.device.binding.id)

      {:ok, request} = Actions.Request.create(binding, payment_attrs())

      assert_in_delta Timex.diff(request.expires_at, Timex.now(), :second), 60, 5
    end

    test "an explicit deadline wins", ctx do
      expires_at = Timex.shift(Timex.now(), seconds: 42)

      {:ok, request} =
        Actions.Request.create(ctx.device.binding, payment_attrs(%{expires_at: expires_at}))

      assert Timex.compare(request.expires_at, expires_at) == 0
    end

    test "a revoked device cannot be asked anything", ctx do
      {:ok, revoked} = Actions.Binding.revoke(ctx.device.binding)

      assert Actions.Request.create(revoked, payment_attrs()) == {:error, :binding_not_active}
    end

    test "the merchant's idempotency key is unique per tenant", ctx do
      attrs = payment_attrs(%{external_id: "order-1"})

      assert {:ok, _request} = Actions.Request.create(ctx.device.binding, attrs)
      assert {:error, changeset} = Actions.Request.create(ctx.device.binding, attrs)
      assert %{external_id: ["has already been taken"]} = errors_on(changeset)

      other = Device.bind(insert(:tenant))
      assert {:ok, _request} = Actions.Request.create(other.binding, attrs)
    end
  end

  describe "decide/4" do
    test "records a confirmation together with its proof", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      signature = Device.decide(ctx.device, request, "confirm")

      assert {:ok, decided} =
               Actions.Request.decide(request, ctx.device.binding, "confirm", signature)

      assert decided.status == :confirmed
      assert decided.decided_at
      assert decided.signature == signature
      assert decided.signature_algorithm == "ecdsa-p256"

      assert decided.signed_payload ==
               Crypto.signing_string(
                 request.id,
                 request.nonce,
                 "confirm",
                 request.payload_hash
               )
    end

    test "records a denial", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert {:ok, decided} =
               Actions.Request.decide(
                 request,
                 ctx.device.binding,
                 "deny",
                 Device.decide(ctx.device, request, "deny")
               )

      assert decided.status == :declined
    end

    test "a signature over the other decision does not pass", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      confirm = Device.decide(ctx.device, request, "confirm")

      assert Actions.Request.decide(request, ctx.device.binding, "deny", confirm) ==
               {:error, :invalid_signature}
    end

    test "a signature from another device does not pass", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      impostor = Device.bind(insert(:tenant))

      assert Actions.Request.decide(
               request,
               ctx.device.binding,
               "confirm",
               Device.decide(impostor, request, "confirm")
             ) == {:error, :invalid_signature}
    end

    test "five bad signatures revoke the binding", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      for _attempt <- 1..Models.Binding.max_failed_attempts() do
        binding = BindingRepo.get!(ctx.device.binding.id)

        assert Actions.Request.decide(request, binding, "confirm", "bad") ==
                 {:error, :invalid_signature}
      end

      assert BindingRepo.get!(ctx.device.binding.id).status == :revoked
    end

    test "a valid signature clears the failure counter", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert Actions.Request.decide(request, ctx.device.binding, "confirm", "bad") ==
               {:error, :invalid_signature}

      binding = BindingRepo.get!(ctx.device.binding.id)
      assert binding.failed_attempts == 1

      {:ok, _decided} =
        Actions.Request.decide(
          request,
          binding,
          "confirm",
          Device.decide(ctx.device, request, "confirm")
        )

      assert BindingRepo.get!(binding.id).failed_attempts == 0
    end

    test "another device cannot answer this request", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      other = Device.bind(ctx.tenant, %{external_id: "customer-other"})

      assert Actions.Request.decide(
               request,
               other.binding,
               "confirm",
               Device.decide(other, request, "confirm")
             ) == {:error, :not_yours}
    end

    test "a decided request cannot be decided again", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      signature = Device.decide(ctx.device, request, "confirm")

      {:ok, decided} = Actions.Request.decide(request, ctx.device.binding, "confirm", signature)

      assert Actions.Request.decide(decided, ctx.device.binding, "confirm", signature) ==
               {:error, :already_decided}
    end

    test "an expired request is refused and closed in passing", ctx do
      {:ok, request} =
        Actions.Request.create(
          ctx.device.binding,
          payment_attrs(%{expires_at: Timex.shift(Timex.now(), seconds: -1)})
        )

      assert Actions.Request.decide(
               request,
               ctx.device.binding,
               "confirm",
               Device.decide(ctx.device, request, "confirm")
             ) == {:error, :expired}

      assert RequestRepo.get!(request.id).status == :expired
    end

    test "an unknown decision word is refused before anything is touched", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

      assert Actions.Request.decide(request, ctx.device.binding, "maybe", "signature") ==
               {:error, :invalid_decision}

      assert RequestRepo.get!(request.id).status == :pending
    end
  end

  test "cancel/1 closes a pending request", ctx do
    {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())

    assert {:ok, cancelled} = Actions.Request.cancel(request)
    assert cancelled.status == :cancelled
    assert Actions.Request.cancel(cancelled) == {:error, :not_pending}
  end

  test "expire_overdue/0 closes requests past their deadline", ctx do
    {:ok, overdue} =
      Actions.Request.create(
        ctx.device.binding,
        payment_attrs(%{expires_at: Timex.shift(Timex.now(), seconds: -1)})
      )

    {:ok, live} = Actions.Request.create(ctx.device.binding, payment_attrs())

    assert [expired] = Actions.Request.expire_overdue()
    assert expired.id == overdue.id
    assert RequestRepo.get!(overdue.id).status == :expired
    assert RequestRepo.get!(live.id).status == :pending
  end

  describe "listing" do
    test "pending requests exclude decided and expired ones", ctx do
      {:ok, pending} = Actions.Request.create(ctx.device.binding, payment_attrs())

      {:ok, _overdue} =
        Actions.Request.create(
          ctx.device.binding,
          payment_attrs(%{expires_at: Timex.shift(Timex.now(), seconds: -1)})
        )

      {:ok, decided} = Actions.Request.create(ctx.device.binding, payment_attrs())

      {:ok, _decided} =
        Actions.Request.decide(
          decided,
          ctx.device.binding,
          "deny",
          Device.decide(ctx.device, decided, "deny")
        )

      assert Enum.map(RequestRepo.list_pending(ctx.device.binding), & &1.id) == [pending.id]
    end

    test "requests are scoped to their binding and tenant", ctx do
      {:ok, request} = Actions.Request.create(ctx.device.binding, payment_attrs())
      other = Device.bind(insert(:tenant))
      {:ok, _other} = Actions.Request.create(other.binding, payment_attrs())

      assert Enum.map(RequestRepo.list_by_binding(ctx.device.binding), & &1.id) == [request.id]
      assert Enum.map(RequestRepo.list_by_tenant(ctx.tenant), & &1.id) == [request.id]
    end

    test "by idempotency key", ctx do
      {:ok, request} =
        Actions.Request.create(ctx.device.binding, payment_attrs(%{external_id: "order-9"}))

      assert {:ok, found} = RequestRepo.get_by_external_id(ctx.tenant, "order-9")
      assert found.id == request.id

      assert RequestRepo.get_by_external_id(insert(:tenant), "order-9") == {:error, :not_found}
    end
  end
end
