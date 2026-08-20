defmodule ScaApi.ApiDocsTest do
  @moduledoc """
  The merchant API's documentation, written as a test.

  Every example in `docs/api.apib` is a call made here against the real
  endpoints, so a response that changes shape breaks this file instead of
  quietly turning the documentation into a lie. `mix api.docs` runs it and
  renders the blueprint; the prose around the examples is `docs/api.intro.md`.

  The device API is deliberately absent: it is a contract with the mobile client
  rather than something a merchant integrates against, and `device_api_test.exs`
  is where it is pinned down.

  Two things this file cares about that an ordinary test does not. The order of
  the calls is the order of the document. And every example of one endpoint has
  to sit next to the others, under the same `title:` — Bureaucrat groups what it
  sees in sequence, so a stray call in between splits an endpoint in two.
  """

  use ScaApi.ConnCase, async: true

  import Bureaucrat.Helpers

  alias Sca.Actions
  alias Sca.Repos.ApiTokenRepo
  alias ScaApi.Fixtures

  @merchant "Merchant API"

  @payment %{
    type: "payment",
    title: "Payment confirmation",
    description: "Transfer to ACME Ltd",
    params: %{amount: "149.90", currency: "EUR", beneficiary: "ACME Ltd"}
  }

  setup %{conn: conn} do
    %{tenant: tenant, api_token: token} = Fixtures.merchant()

    %{conn: merchant_conn(conn, token), tenant: tenant}
  end

  describe "the merchant API" do
    test "enrolling a device", ctx do
      ctx.conn
      |> with_key("enroll-4471")
      |> post(~p"/api/merchant/v1/bindings", %{
        external_id: "customer-4471",
        name: "Dana's iPhone"
      })
      |> doc(
        group_title: @merchant,
        title: "Enrol a device",
        description: "A person enrolling for the first time",
        detail: """
        Starts an enrollment and answers with the activation code.

        `activation.qr_payload` is the exact string to encode into a QR — the
        phone reads our address out of it, so nothing about us has to sit in
        your configuration. The code is good for 15 minutes.

        `external_id` is your own identifier for the person. Enrolling it again
        replaces that person's device, which is how a lost phone is replaced, so
        the retry key here is the `Idempotency-Key` header instead.
        """
      )
      |> json_response(201)

      ctx.conn
      |> with_key("enroll-4471")
      |> post(~p"/api/merchant/v1/bindings", %{
        external_id: "customer-4471",
        name: "Dana's iPhone"
      })
      |> doc(
        group_title: @merchant,
        title: "Enrol a device",
        description: "The same call again, same key"
      )
      |> json_response(200)

      ctx.conn
      |> post(~p"/api/merchant/v1/bindings", %{name: "Dana's iPhone"})
      |> doc(
        group_title: @merchant,
        title: "Enrol a device",
        description: "Without a reference of your own"
      )
      |> json_response(422)
    end

    test "listing the devices you enrolled", ctx do
      _device = Fixtures.device(ctx.tenant, "customer-4471")

      ctx.conn
      |> get(~p"/api/merchant/v1/bindings?page=1&page_size=50")
      |> doc(
        group_title: @merchant,
        title: "List devices",
        description: "The first page",
        detail: """
        Your devices, newest first. `page` counts from 1, `page_size` is 50 by
        default and 100 at most.
        """
      )
      |> json_response(200)

      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{revoked_key()}")
      |> get(~p"/api/merchant/v1/bindings")
      |> plug_doc(module: ScaApi.MerchantController, action: :list_bindings)
      |> doc(
        group_title: @merchant,
        title: "List devices",
        description: "With a key that has been revoked"
      )
      |> json_response(401)
    end

    test "looking one device up", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")

      ctx.conn
      |> get(~p"/api/merchant/v1/bindings/#{device.binding.id}")
      |> doc(
        group_title: @merchant,
        title: "Fetch a device",
        description: "By its id",
        detail: """
        Takes the binding's uuid or your own `external_id` — whichever you kept.
        A device belonging to another merchant is `404`, not `403`.
        """
      )
      |> json_response(200)

      ctx.conn
      |> get(~p"/api/merchant/v1/bindings/customer-nobody")
      |> doc(
        group_title: @merchant,
        title: "Fetch a device",
        description: "A reference nobody here has"
      )
      |> json_response(404)
    end

    test "retiring a device", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")

      ctx.conn
      |> post(~p"/api/merchant/v1/bindings/#{device.binding.id}/revoke")
      |> doc(
        group_title: @merchant,
        title: "Revoke a device",
        description: "The phone is gone",
        detail: """
        Final: nothing can be asked of the device again and the app stops
        working on the next call. The person enrols anew to get a new one.
        """
      )
      |> json_response(200)
    end

    test "asking for an approval", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")
      revoked = Fixtures.device(ctx.tenant, "customer-9002")
      {:ok, _binding} = Actions.Binding.revoke(revoked.binding)

      payment = Map.merge(@payment, %{binding: device.binding.id, external_id: "order-4471"})

      ctx.conn
      |> post(~p"/api/merchant/v1/approvals", payment)
      |> doc(
        group_title: @merchant,
        title: "Ask for an approval",
        description: "A payment, on a device named by its id",
        detail: """
        Raises the card on the phone and pushes a notification at it.

        `binding` takes the device's uuid or your own `external_id` for its
        owner. `external_id` on the approval itself is your reference for what
        is being approved, and doubles as the retry key.

        `params` is what the user sees and what the signature covers: a flat
        object of scalars, at most 20 of them. A `payment` needs `amount`,
        `currency` and `beneficiary`; a `login` needs `ip`; a `freeform` insists
        on nothing. Add fields of your own and they are shown as extra rows.

        Without `expires_at` the merchant default applies — 5 minutes, set in
        the console.
        """
      )
      |> json_response(201)

      ctx.conn
      |> post(~p"/api/merchant/v1/approvals", payment)
      |> doc(
        group_title: @merchant,
        title: "Ask for an approval",
        description: "The same reference again"
      )
      |> json_response(200)

      ctx.conn
      |> post(~p"/api/merchant/v1/approvals", %{
        binding: "customer-4471",
        type: "payment",
        title: "Payment confirmation",
        params: %{amount: "149.90"}
      })
      |> doc(
        group_title: @merchant,
        title: "Ask for an approval",
        description: "Params a payment cannot go without"
      )
      |> json_response(422)

      ctx.conn
      |> post(~p"/api/merchant/v1/approvals", Map.put(@payment, :binding, revoked.binding.id))
      |> doc(
        group_title: @merchant,
        title: "Ask for an approval",
        description: "On a device that was revoked"
      )
      |> json_response(409)
    end

    test "listing approvals", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")
      {:ok, _request} = Actions.Request.create(device.binding, approval_attrs())

      ctx.conn
      |> get(~p"/api/merchant/v1/approvals?page=1&page_size=50")
      |> doc(
        group_title: @merchant,
        title: "List approvals",
        description: "The first page",
        detail: "Your approvals, newest first, each with the device it was raised on."
      )
      |> json_response(200)
    end

    test "reading the answer off an approval", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")
      {:ok, request} = Actions.Request.create(device.binding, approval_attrs())
      {:ok, confirmed} = confirm(device, request)

      ctx.conn
      |> get(~p"/api/merchant/v1/approvals/#{confirmed.id}")
      |> doc(
        group_title: @merchant,
        title: "Fetch an approval",
        description: "One the user confirmed",
        detail: """
        What a webhook would have told you, for anyone who would rather poll.

        Once it is answered, the approval carries the evidence: `signature`,
        `signed_payload` — the exact string the device signed — and
        `payload_hash`, the hash of the params it covers.
        """
      )
      |> json_response(200)
    end

    test "taking an approval back", ctx do
      device = Fixtures.device(ctx.tenant, "customer-4471")
      {:ok, request} = Actions.Request.create(device.binding, approval_attrs())

      ctx.conn
      |> post(~p"/api/merchant/v1/approvals/#{request.id}/cancel")
      |> doc(
        group_title: @merchant,
        title: "Cancel an approval",
        description: "Nobody had answered it yet",
        detail: """
        Closes a card the user has not answered. One that was already answered,
        cancelled or expired is `409 not_pending`.
        """
      )
      |> json_response(200)
    end
  end

  defp merchant_conn(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp with_key(conn, key), do: Plug.Conn.put_req_header(conn, "idempotency-key", key)

  defp revoked_key do
    %{api_token: token} = Fixtures.merchant()
    {:ok, api_token} = ApiTokenRepo.get_by_token(token)
    {:ok, _revoked} = Actions.ApiToken.revoke(api_token)

    token
  end

  defp approval_attrs do
    %{
      external_id: "order-4471",
      type: :payment,
      title: @payment.title,
      description: @payment.description,
      payload: %{
        "amount" => "149.90",
        "currency" => "EUR",
        "beneficiary" => "ACME Ltd"
      }
    }
  end

  defp confirm(device, request) do
    signature = Fixtures.sign_decision(device, request, "confirm")

    Actions.Request.decide(request, device.binding, "confirm", signature)
  end
end
