defmodule ScaApi.MerchantApiTest do
  @moduledoc "The API a merchant's server calls, and the key that opens it."

  use ScaApi.ConnCase, async: true

  alias Sca.Actions
  alias Sca.Repos.ApiTokenRepo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Repos.WebhookDeliveryRepo
  alias ScaApi.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, api_token: token} = Fixtures.merchant()

    %{conn: authorized(conn, token), tenant: tenant, api_token: token}
  end

  defp with_key(conn, key), do: Plug.Conn.put_req_header(conn, "idempotency-key", key)

  defp authorized(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  describe "the key" do
    test "a request without one is refused", %{tenant: _tenant} do
      conn = Phoenix.ConnTest.build_conn() |> get(~p"/api/merchant/v1/bindings")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "a revoked key stops working", ctx do
      {:ok, api_token} = ApiTokenRepo.get_by_token(ctx.api_token)
      {:ok, _revoked} = Actions.ApiToken.revoke(api_token)

      assert ctx.conn |> get(~p"/api/merchant/v1/bindings") |> json_response(401)
    end

    test "a suspended merchant is told why", ctx do
      {:ok, _tenant} = Actions.Tenant.deactivate(ctx.tenant)

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings")

      assert %{"error" => %{"code" => "merchant_suspended"}} = json_response(conn, 403)
    end

    test "using a key marks it as used", ctx do
      get(ctx.conn, ~p"/api/merchant/v1/bindings")

      assert {:ok, %{last_used_at: %DateTime{}}} = ApiTokenRepo.get_by_token(ctx.api_token)
    end
  end

  describe "bindings" do
    test "creating one returns the activation code and its deadline", ctx do
      conn =
        post(ctx.conn, ~p"/api/merchant/v1/bindings", %{
          external_id: "customer-4471",
          name: "Dana's iPhone"
        })

      assert %{"id" => id, "external_id" => "customer-4471", "status" => "pending"} =
               body = json_response(conn, 201)

      assert {:ok, _uuid} = Ecto.UUID.cast(id)
      assert %{"code" => code, "nonce" => nonce, "expires_at" => expires_at} = body["activation"]
      assert is_binary(code) and is_binary(nonce) and is_binary(expires_at)
    end

    test "a missing reference is a validation error, with the field named", ctx do
      conn = post(ctx.conn, ~p"/api/merchant/v1/bindings", %{})

      assert %{"error" => %{"code" => "invalid_request", "fields" => fields}} =
               json_response(conn, 422)

      assert fields["external_id"] == ["can't be blank"]
    end

    test "listing pages and shows only this merchant's devices", ctx do
      device = Fixtures.device(ctx.tenant)
      stranger = Fixtures.merchant()
      _theirs = Fixtures.device(stranger.tenant, "customer-9")

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings")

      assert %{"data" => [binding], "page" => %{"total_count" => 1}} = json_response(conn, 200)
      assert binding["id"] == device.binding.id
    end

    test "the page size in the query is honoured, up to a hundred", ctx do
      for index <- 1..3, do: Fixtures.device(ctx.tenant, "customer-#{index}")

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings?page=1&page_size=2")

      assert %{"data" => [_one, _two], "page" => page} = json_response(conn, 200)
      assert page["size"] == 2
      assert page["total_count"] == 3

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings?page_size=500")

      assert %{"page" => %{"size" => 100}} = json_response(conn, 200)
    end

    test "revoking retires the device", ctx do
      device = Fixtures.device(ctx.tenant)

      conn = post(ctx.conn, ~p"/api/merchant/v1/bindings/#{device.binding.id}/revoke")

      assert %{"status" => "revoked"} = json_response(conn, 200)
    end

    test "another merchant's device is not found", ctx do
      stranger = Fixtures.merchant()
      theirs = Fixtures.device(stranger.tenant, "customer-9")

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings/#{theirs.binding.id}")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  test "an enrollment carries everything needed to draw the QR", ctx do
    conn = post(ctx.conn, ~p"/api/merchant/v1/bindings", %{external_id: "customer-1"})

    assert %{"activation" => activation} = json_response(conn, 201)
    assert %{"code" => code, "nonce" => nonce, "connect_url" => url} = activation

    # The merchant keeps no address of ours in their own configuration.
    assert url =~ ~r{^https?://.+/t/#{ctx.tenant.id}$}

    # And nothing has to be assembled on their side either: this string is what
    # goes into the QR, and it is what the mobile client parses.
    payload = Jason.decode!(activation["qr_payload"])

    assert payload["type"] == "sca-proto-enroll"
    assert payload["connect_url"] == url
    assert payload["connect_token"] == code
    assert payload["nonce"] == nonce
  end

  test "a webhook names the same thing the API just answered with", ctx do
    {:ok, tenant} =
      Actions.Tenant.update_settings(ctx.tenant, %{webhook_url: "https://merchant.example.com/x"})

    device = Fixtures.device(tenant)

    body = %{
      binding: device.binding.id,
      type: "login",
      title: "Sign in",
      params: %{ip: "1.2.3.4"}
    }

    assert %{"id" => id} =
             ctx.conn |> post(~p"/api/merchant/v1/approvals", body) |> json_response(201)

    # Otherwise a merchant cannot tell which call a webhook is about.
    delivery =
      tenant
      |> WebhookDeliveryRepo.list_by_tenant()
      |> Enum.find(&(&1.event == "request.created"))

    assert delivery.payload["request"]["id"] == id
    assert delivery.payload["binding"]["id"] == device.binding.id
  end

  describe "idempotency" do
    test "a repeated enrollment answers with the first one, code and all", ctx do
      body = %{external_id: "customer-1", name: "Dana's iPhone"}

      first =
        ctx.conn |> with_key("enroll-key-1") |> post(~p"/api/merchant/v1/bindings", body)

      assert %{"id" => id, "activation" => %{"code" => code}} = json_response(first, 201)

      second =
        ctx.conn |> with_key("enroll-key-1") |> post(~p"/api/merchant/v1/bindings", body)

      # Not 201: nothing was created this time. And the same activation code,
      # because the merchant may already be showing it as a QR.
      assert %{"id" => ^id, "activation" => %{"code" => ^code}} = json_response(second, 200)
      assert BindingRepo.list_by_tenant(ctx.tenant) |> length() == 1
    end

    test "a merchant's own reference is the key: no header needed", ctx do
      device = Fixtures.device(ctx.tenant)

      body = %{
        binding: device.binding.id,
        external_id: "order-4471",
        type: "payment",
        title: "Payment confirmation",
        params: %{amount: "10.00", currency: "EUR", beneficiary: "ACME"}
      }

      assert %{"id" => id, "external_id" => "order-4471"} =
               ctx.conn |> post(~p"/api/merchant/v1/approvals", body) |> json_response(201)

      assert %{"id" => ^id} =
               ctx.conn |> post(~p"/api/merchant/v1/approvals", body) |> json_response(200)

      assert [_one] = RequestRepo.list_pending(device.binding)
    end

    test "the header fills the reference in when the body has none", ctx do
      device = Fixtures.device(ctx.tenant)

      body = %{
        binding: device.binding.id,
        type: "login",
        title: "Sign in",
        params: %{ip: "1.2.3.4"}
      }

      assert %{"external_id" => "header-key-1"} =
               ctx.conn
               |> with_key("header-key-1")
               |> post(~p"/api/merchant/v1/approvals", body)
               |> json_response(201)
    end

    test "a repeated approval raises one card, not two", ctx do
      device = Fixtures.device(ctx.tenant)

      body = %{
        binding: device.binding.id,
        type: "login",
        title: "Sign in",
        params: %{ip: "1.2.3.4"}
      }

      first = ctx.conn |> with_key("raise-key-1") |> post(~p"/api/merchant/v1/approvals", body)
      assert %{"id" => id} = json_response(first, 201)

      second = ctx.conn |> with_key("raise-key-1") |> post(~p"/api/merchant/v1/approvals", body)
      assert %{"id" => ^id} = json_response(second, 200)

      assert [_one] = RequestRepo.list_pending(device.binding)
    end

    test "the key wins over the body: a second call raises nothing new", ctx do
      device = Fixtures.device(ctx.tenant)

      first =
        ctx.conn
        |> with_key("raise-key-2")
        |> post(~p"/api/merchant/v1/approvals", %{
          binding: device.binding.id,
          type: "login",
          title: "Sign in",
          params: %{ip: "1.2.3.4"}
        })

      assert %{"id" => id} = json_response(first, 201)

      second =
        ctx.conn
        |> with_key("raise-key-2")
        |> post(~p"/api/merchant/v1/approvals", %{
          binding: device.binding.id,
          type: "login",
          title: "Sign in somewhere else",
          params: %{ip: "5.6.7.8"}
        })

      # The key says "this call", so the first card is the answer — the device
      # is already showing it, and a second one would be the bug.
      assert %{"id" => ^id, "title" => "Sign in"} = json_response(second, 200)
      assert [_one] = RequestRepo.list_pending(device.binding)
    end

    test "a key belongs to one merchant's data, not to a device of another", ctx do
      device = Fixtures.device(ctx.tenant)
      %{tenant: other, api_token: other_token} = Fixtures.merchant()
      theirs = Fixtures.device(other)

      body = %{type: "login", title: "Sign in", params: %{ip: "1.2.3.4"}}

      assert %{"id" => mine} =
               ctx.conn
               |> with_key("same-key")
               |> post(~p"/api/merchant/v1/approvals", Map.put(body, :binding, device.binding.id))
               |> json_response(201)

      assert %{"id" => not_mine} =
               Phoenix.ConnTest.build_conn()
               |> authorized(other_token)
               |> with_key("same-key")
               |> post(~p"/api/merchant/v1/approvals", Map.put(body, :binding, theirs.binding.id))
               |> json_response(201)

      refute mine == not_mine
    end

    test "without the header every call is its own", ctx do
      body = %{external_id: "customer-1"}

      assert %{"id" => first} =
               ctx.conn |> post(~p"/api/merchant/v1/bindings", body) |> json_response(201)

      assert %{"id" => second} =
               ctx.conn |> post(~p"/api/merchant/v1/bindings", body) |> json_response(201)

      # Same person, so the same binding row is reused — but a fresh code, which
      # is exactly what an unkeyed retry cannot avoid.
      assert first == second
    end

    test "one merchant's key means nothing to another", ctx do
      %{tenant: other, api_token: other_token} = Fixtures.merchant()
      body = %{external_id: "customer-1"}

      ctx.conn |> with_key("shared-key") |> post(~p"/api/merchant/v1/bindings", body)

      conn =
        Phoenix.ConnTest.build_conn()
        |> authorized(other_token)
        |> with_key("shared-key")
        |> post(~p"/api/merchant/v1/bindings", body)

      assert %{"id" => id} = json_response(conn, 201)
      assert {:ok, binding} = BindingRepo.get(id)
      assert binding.tenant_id == other.id
    end
  end

  describe "approvals" do
    setup ctx, do: Map.put(ctx, :device, Fixtures.device(ctx.tenant))

    test "raising one by the merchant's own reference", ctx do
      conn =
        post(ctx.conn, ~p"/api/merchant/v1/approvals", %{
          binding: "customer-1",
          type: "payment",
          title: "Payment confirmation",
          params: %{amount: "149.90", currency: "EUR", beneficiary: "ACME Ltd"}
        })

      assert %{"id" => id, "status" => "pending", "payload_hash" => hash} =
               body = json_response(conn, 201)

      assert {:ok, _uuid} = Ecto.UUID.cast(id)
      assert byte_size(hash) == 64
      assert body["params"]["amount"] == "149.90"
      assert body["binding"]["external_id"] == "customer-1"
    end

    test "params are validated per type, against the field that was sent", ctx do
      conn =
        post(ctx.conn, ~p"/api/merchant/v1/approvals", %{
          binding: "customer-1",
          type: "payment",
          title: "Payment confirmation",
          params: %{amount: "149.90"}
        })

      assert %{"error" => %{"fields" => fields}} = json_response(conn, 422)
      assert fields["currency"] == ["is required for a payment request"]
    end

    test "a revoked device cannot be asked anything", ctx do
      {:ok, _binding} = Actions.Binding.revoke(ctx.device.binding)

      conn =
        post(ctx.conn, ~p"/api/merchant/v1/approvals", %{
          binding: "customer-1",
          type: "freeform",
          title: "Confirm"
        })

      assert %{"error" => %{"code" => "binding_not_active"}} = json_response(conn, 409)
    end

    test "listing and cancelling", ctx do
      {:ok, request} =
        Actions.Request.create(ctx.device.binding, %{
          type: :freeform,
          title: "Confirm",
          payload: %{"note" => "hello"}
        })

      assert %{"data" => [listed]} =
               ctx.conn |> get(~p"/api/merchant/v1/approvals") |> json_response(200)

      assert listed["id"] == request.id

      conn = post(ctx.conn, ~p"/api/merchant/v1/approvals/#{request.id}/cancel")
      assert %{"status" => "cancelled"} = json_response(conn, 200)

      conn = post(ctx.conn, ~p"/api/merchant/v1/approvals/#{request.id}/cancel")
      assert %{"error" => %{"code" => "not_pending"}} = json_response(conn, 409)
    end
  end
end
