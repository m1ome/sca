defmodule ScaApi.MerchantApiTest do
  @moduledoc "The API a merchant's server calls, and the key that opens it."

  use ScaApi.ConnCase, async: true

  alias Sca.Actions
  alias Sca.Repos.ApiTokenRepo
  alias ScaApi.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, api_token: token} = Fixtures.merchant()

    %{conn: authorized(conn, token), tenant: tenant, api_token: token}
  end

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

      assert id =~ ~r/\ABIN-\d+\z/
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
      assert binding["id"] == device.binding.public_id
    end

    test "revoking retires the device", ctx do
      device = Fixtures.device(ctx.tenant)

      conn = post(ctx.conn, ~p"/api/merchant/v1/bindings/#{device.binding.public_id}/revoke")

      assert %{"status" => "revoked"} = json_response(conn, 200)
    end

    test "another merchant's device is not found", ctx do
      stranger = Fixtures.merchant()
      theirs = Fixtures.device(stranger.tenant, "customer-9")

      conn = get(ctx.conn, ~p"/api/merchant/v1/bindings/#{theirs.binding.public_id}")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
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

      assert id =~ ~r/\AREQ-\d+\z/
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

      assert listed["id"] == request.public_id

      conn = post(ctx.conn, ~p"/api/merchant/v1/approvals/#{request.public_id}/cancel")
      assert %{"status" => "cancelled"} = json_response(conn, 200)

      conn = post(ctx.conn, ~p"/api/merchant/v1/approvals/#{request.public_id}/cancel")
      assert %{"error" => %{"code" => "not_pending"}} = json_response(conn, 409)
    end
  end
end
