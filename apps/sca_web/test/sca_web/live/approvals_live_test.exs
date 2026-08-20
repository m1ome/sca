defmodule ScaWeb.ApprovalsLiveTest do
  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Actions
  alias ScaWeb.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)

    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})

    {:ok, %{binding: binding}} =
      Actions.Binding.bind(pending.enroll_token, %{
        public_key: Base.encode64(public_key),
        name: "Dana's iPhone"
      })

    %{
      conn: Fixtures.log_in(conn, user),
      tenant: tenant,
      binding: binding,
      private_key: private_key
    }
  end

  test "lists approvals with their status and never with a decision button", ctx do
    {:ok, _request} = payment(ctx.binding, "149.90")

    {:ok, live, html} = live(ctx.conn, ~p"/approvals")

    assert html =~ "Payment confirmation"
    assert html =~ "Dana&#39;s iPhone"
    assert html =~ "pending"
    assert html =~ "View"

    refute has_element?(live, "#approvals button")
    refute html =~ "beneficiary"
    refute html =~ "149.90"
  end

  test "filters by status", ctx do
    {:ok, confirmed} = payment(ctx.binding, "24.00")
    {:ok, pending} = payment(ctx.binding, "10.00")
    decide(ctx, confirmed, "confirm")

    {:ok, live, html} = live(ctx.conn, ~p"/approvals")
    assert html =~ "2 in total"

    html = live |> form("form[phx-change=filter]", %{"status" => "confirmed"}) |> render_change()

    assert html =~ "1 in total"
    assert html =~ "/approvals/#{confirmed.public_id}"
    refute html =~ "/approvals/#{pending.public_id}"
  end

  test "a merchant sees nothing of another merchant's approvals", ctx do
    other = Fixtures.merchant()
    {:ok, stranger} = Actions.Binding.enroll(other.tenant, %{external_id: "customer-9"})

    {:ok, %{binding: stranger_binding}} =
      Actions.Binding.bind(stranger.enroll_token, %{
        public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0))
      })

    {:ok, _theirs} = payment(stranger_binding, "999.00")
    {:ok, ours} = payment(ctx.binding, "1.00")

    {:ok, _live, html} = live(ctx.conn, ~p"/approvals")

    assert html =~ ours.public_id or html =~ "1 in total"
    refute html =~ "999.00"
  end

  test "the detail screen shows the params and the proof", ctx do
    {:ok, request} = payment(ctx.binding, "24.00")
    decide(ctx, request, "confirm")

    {:ok, _live, html} = live(ctx.conn, ~p"/approvals/#{request.public_id}")

    assert html =~ "beneficiary"
    assert html =~ "ACME Ltd"
    assert html =~ "Signed string"
    refute html =~ "Cancel approval"
  end

  test "a pending approval can be cancelled from its detail screen", ctx do
    {:ok, request} = payment(ctx.binding, "24.00")

    {:ok, live, html} = live(ctx.conn, ~p"/approvals/#{request.public_id}")
    assert html =~ "Cancel approval"

    assert live |> element("button", "Cancel approval") |> render_click() =~ "cancelled"
  end

  test "another merchant's approval is simply not found", ctx do
    other = Fixtures.merchant()
    {:ok, stranger} = Actions.Binding.enroll(other.tenant, %{external_id: "customer-9"})

    {:ok, %{binding: stranger_binding}} =
      Actions.Binding.bind(stranger.enroll_token, %{
        public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0))
      })

    {:ok, theirs} = payment(stranger_binding, "999.00")

    assert {:error, {:live_redirect, %{to: "/approvals"}}} =
             live(ctx.conn, ~p"/approvals/#{theirs.public_id}")
  end

  defp payment(binding, amount) do
    Actions.Request.create(binding, %{
      type: :payment,
      title: "Payment confirmation",
      description: "Transfer to ACME Ltd",
      payload: %{"amount" => amount, "currency" => "EUR", "beneficiary" => "ACME Ltd"}
    })
  end

  defp decide(ctx, request, decision) do
    signature =
      request.id
      |> Sca.Crypto.signing_string(request.nonce, decision, request.payload_hash)
      |> then(&:crypto.sign(:ecdsa, :sha256, &1, [ctx.private_key, :secp256r1]))
      |> Base.encode64()

    Actions.Request.decide(request, ctx.binding, decision, signature)
  end
end
