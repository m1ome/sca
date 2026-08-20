defmodule ScaApi.DeviceApiTest do
  @moduledoc """
  The API the phone talks to.

  Written against what the mobile client actually parses: field names, status
  codes and the difference between 401 and 403 are a contract with an app that
  is already installed.
  """

  use ScaApi.ConnCase, async: true

  alias Sca.Actions
  alias Sca.Repos.BindingRepo
  alias ScaApi.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant} = Fixtures.merchant()

    %{conn: Plug.Conn.put_req_header(conn, "content-type", "application/json"), tenant: tenant}
  end

  defp as_device(conn, device) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{device.access_token}")
  end

  defp payment(binding) do
    {:ok, request} =
      Actions.Request.create(binding, %{
        type: :payment,
        title: "Payment confirmation",
        description: "Transfer to ACME Ltd",
        payload: %{"amount" => "149.90", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
      })

    request
  end

  test "healthz answers before any binding exists", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get(~p"/healthz") |> json_response(200)
  end

  describe "the merchant in the path" do
    test "a device binds and then keeps working under the prefix", ctx do
      {:ok, pending} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-path"})
      {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)
      prefix = "/t/#{ctx.tenant.public_id}"

      session =
        ctx.conn
        |> post("#{prefix}/api/sca/v1/connections", %{
          connect_token: pending.enroll_token,
          public_key: Base.encode64(public),
          algorithm: "ecdsa-p256"
        })
        |> json_response(201)

      assert %{"access_token" => token} = session

      assert [] =
               ctx.conn
               |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
               |> get("#{prefix}/api/sca/v1/authorizations")
               |> json_response(200)

      assert %{"status" => "ok"} = ctx.conn |> get("#{prefix}/healthz") |> json_response(200)
    end

    test "a code offered under another merchant binds nothing", ctx do
      {:ok, pending} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-wrong"})
      %{tenant: other} = Fixtures.merchant()
      {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)

      assert %{"error" => %{"code" => "unknown_merchant"}} =
               ctx.conn
               |> post("/t/#{other.public_id}/api/sca/v1/connections", %{
                 connect_token: pending.enroll_token,
                 public_key: Base.encode64(public),
                 algorithm: "ecdsa-p256"
               })
               |> json_response(404)

      # The code is still unspent, so the phone can scan it under the right one.
      {:ok, unchanged} = BindingRepo.get(pending.id)
      assert unchanged.status == :pending
      assert unchanged.enroll_token == pending.enroll_token
    end

    test "a session presented under another merchant is not found", ctx do
      device = Fixtures.device(ctx.tenant)
      %{tenant: other} = Fixtures.merchant()

      assert %{"error" => %{"code" => "unknown_merchant"}} =
               ctx.conn
               |> as_device(device)
               |> get("/t/#{other.public_id}/api/sca/v1/authorizations")
               |> json_response(404)
    end

    test "a merchant that does not exist is refused before anything else", ctx do
      device = Fixtures.device(ctx.tenant)

      assert %{"error" => %{"code" => "unknown_merchant"}} =
               ctx.conn
               |> as_device(device)
               |> get("/t/TNT-999999/api/sca/v1/authorizations")
               |> json_response(404)
    end
  end

  describe "binding" do
    test "a scanned code becomes a session", ctx do
      {:ok, pending} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-1"})
      {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)

      conn =
        post(ctx.conn, ~p"/api/sca/v1/connections", %{
          connect_token: pending.enroll_token,
          name: "Test device",
          public_key: Base.encode64(public),
          algorithm: "ecdsa-p256",
          device_info: %{"model" => "iPhone 15"},
          push_platform: "ios",
          push_token: "apns-token"
        })

      assert %{
               "connection_id" => connection_id,
               "access_token" => access_token,
               "status" => "active",
               "access_token_expires_at" => expires_at
             } = json_response(conn, 201)

      assert {:ok, binding} = BindingRepo.get(connection_id)
      assert binding.push_platform == :ios
      assert is_binary(access_token) and is_binary(expires_at)
    end

    test "a code that was already used is a conflict", ctx do
      device = Fixtures.device(ctx.tenant)
      {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)

      conn =
        post(ctx.conn, ~p"/api/sca/v1/connections", %{
          connect_token: "whatever",
          public_key: Base.encode64(public)
        })

      assert %{"error" => %{"code" => "unknown_code"}} = json_response(conn, 404)
      assert device.binding.status == :active
    end

    test "a key that is not a P-256 point is rejected with the field named", ctx do
      {:ok, pending} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-1"})

      conn =
        post(ctx.conn, ~p"/api/sca/v1/connections", %{
          connect_token: pending.enroll_token,
          public_key: "not-a-key"
        })

      assert %{"error" => %{"fields" => %{"public_key" => [_message]}}} = json_response(conn, 422)
    end
  end

  describe "authorizations" do
    setup ctx do
      device = Fixtures.device(ctx.tenant)

      %{device: device, conn: as_device(ctx.conn, device)}
    end

    test "pending returns the card in the shape the client parses", ctx do
      request = payment(ctx.device.binding)

      assert [card] = ctx.conn |> get(~p"/api/sca/v1/authorizations") |> json_response(200)

      assert card["id"] == request.id
      assert card["type"] == "payment"
      assert card["params"]["amount"] == "149.90"
      assert card["payload_hash"] == request.payload_hash
      assert card["nonce"] == request.nonce
      assert card["status"] == "pending"
    end

    test "one card by id, and somebody else's is not found", ctx do
      request = payment(ctx.device.binding)

      assert %{"id" => id} =
               ctx.conn |> get(~p"/api/sca/v1/authorizations/#{request.id}") |> json_response(200)

      assert id == request.id

      stranger = Fixtures.device(ctx.tenant, "customer-2")
      theirs = payment(stranger.binding)

      assert ctx.conn |> get(~p"/api/sca/v1/authorizations/#{theirs.id}") |> json_response(404)
    end

    test "a signed confirmation is accepted and comes back with its proof", ctx do
      request = payment(ctx.device.binding)
      signature = Fixtures.sign_decision(ctx.device, request, "confirm")

      conn =
        put(ctx.conn, ~p"/api/sca/v1/authorizations/#{request.id}", %{
          decision: "confirm",
          signature: signature
        })

      assert %{"status" => "confirmed", "signature" => ^signature, "signed_payload" => signed} =
               json_response(conn, 200)

      assert signed =~ "sca-service:v1:#{request.id}"
    end

    test "a bad signature is refused and counted", ctx do
      request = payment(ctx.device.binding)

      conn =
        put(ctx.conn, ~p"/api/sca/v1/authorizations/#{request.id}", %{
          decision: "confirm",
          signature: "nonsense"
        })

      assert %{"error" => %{"code" => "invalid_signature"}} = json_response(conn, 400)
      assert {:ok, %{failed_attempts: 1}} = BindingRepo.get(ctx.device.binding.id)
    end

    test "answering twice is a conflict, and an expired card is gone", ctx do
      request = payment(ctx.device.binding)
      signature = Fixtures.sign_decision(ctx.device, request, "confirm")

      put(ctx.conn, ~p"/api/sca/v1/authorizations/#{request.id}", %{
        decision: "confirm",
        signature: signature
      })

      conn =
        put(ctx.conn, ~p"/api/sca/v1/authorizations/#{request.id}", %{
          decision: "confirm",
          signature: signature
        })

      assert %{"error" => %{"code" => "already_decided"}} = json_response(conn, 409)

      {:ok, overdue} =
        Actions.Request.create(
          ctx.device.binding,
          %{
            type: :freeform,
            title: "Late",
            expires_at: Timex.shift(Timex.now(), seconds: -1)
          }
        )

      conn =
        put(ctx.conn, ~p"/api/sca/v1/authorizations/#{overdue.id}", %{
          decision: "confirm",
          signature: Fixtures.sign_decision(ctx.device, overdue, "confirm")
        })

      assert %{"error" => %{"code" => "expired"}} = json_response(conn, 410)
    end
  end

  describe "the session" do
    setup ctx do
      device = Fixtures.device(ctx.tenant)

      %{device: device, conn: as_device(ctx.conn, device)}
    end

    test "a revoked binding answers 403, an expired token answers 401", ctx do
      expire(ctx.device.binding, -1)

      assert %{"error" => %{"code" => "token_expired"}} =
               ctx.conn |> get(~p"/api/sca/v1/authorizations") |> json_response(401)

      {:ok, _binding} = Actions.Binding.revoke(ctx.device.binding)

      # A revoked binding has no session left, so the token stops resolving.
      assert ctx.conn |> get(~p"/api/sca/v1/authorizations") |> json_response(401)
    end

    test "an expired token may still renew itself with a hardware signature", ctx do
      expire(ctx.device.binding, -1)

      assert %{"nonce" => nonce} =
               ctx.conn
               |> post(~p"/api/sca/v1/connections/self/refresh/challenge")
               |> json_response(200)

      conn =
        post(ctx.conn, ~p"/api/sca/v1/connections/self/refresh", %{
          signature: Fixtures.sign_refresh(ctx.device, nonce)
        })

      assert %{"access_token_expires_at" => expires_at} = json_response(conn, 200)
      assert {:ok, renewed, _offset} = DateTime.from_iso8601(expires_at)
      assert Timex.after?(renewed, Timex.now())

      assert ctx.conn |> get(~p"/api/sca/v1/authorizations") |> json_response(200)
    end

    test "a stolen bearer alone cannot renew", ctx do
      thief = Fixtures.device(ctx.tenant, "customer-2")

      assert %{"nonce" => nonce} =
               ctx.conn
               |> post(~p"/api/sca/v1/connections/self/refresh/challenge")
               |> json_response(200)

      conn =
        post(ctx.conn, ~p"/api/sca/v1/connections/self/refresh", %{
          signature: Fixtures.sign_refresh(thief, nonce)
        })

      assert %{"error" => %{"code" => "invalid_proof"}} = json_response(conn, 400)
    end

    test "the push token can be re-registered", ctx do
      conn =
        put(ctx.conn, ~p"/api/sca/v1/connections/self/push-token", %{
          push_token: "new-apns-token",
          push_platform: "ios"
        })

      assert %{"status" => "updated"} = json_response(conn, 200)
      assert {:ok, %{push_token: "new-apns-token"}} = BindingRepo.get(ctx.device.binding.id)
    end

    test "a device unbinds itself, and only itself", ctx do
      other = Fixtures.device(ctx.tenant, "customer-2")

      assert ctx.conn
             |> post(~p"/api/sca/v1/connections/#{other.binding.id}/revoke")
             |> json_response(404)

      assert %{"status" => "revoked"} =
               ctx.conn
               |> post(~p"/api/sca/v1/connections/#{ctx.device.binding.id}/revoke")
               |> json_response(200)

      assert {:ok, %{status: :revoked}} = BindingRepo.get(ctx.device.binding.id)
    end
  end

  defp expire(binding, seconds) do
    Sca.Repos.BindingRepo.change(binding,
      access_token_expires_at: Timex.shift(Timex.now(), seconds: seconds)
    )
  end
end
