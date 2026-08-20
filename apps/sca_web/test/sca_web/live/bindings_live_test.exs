defmodule ScaWeb.BindingsLiveTest do
  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Actions
  alias Sca.Repos.BindingRepo
  alias ScaWeb.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()

    %{conn: Fixtures.log_in(conn, user), tenant: tenant}
  end

  defp bind(tenant, external_id, name) do
    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: external_id})

    {:ok, %{binding: binding}} =
      Actions.Binding.bind(pending.enroll_token, %{
        public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0)),
        name: name,
        push_platform: :ios,
        push_token: "push-#{external_id}"
      })

    binding
  end

  test "lists devices with their state, and nothing that acts on them", ctx do
    binding = bind(ctx.tenant, "customer-1", "Dana's iPhone")

    {:ok, live, html} = live(ctx.conn, ~p"/bindings")

    assert html =~ "Dana&#39;s iPhone"
    assert html =~ "customer-1"
    assert html =~ "IOS"
    assert html =~ "active"
    assert html =~ "/bindings/#{binding.public_id}"
    # By element, not by string: "Revoked" is a legitimate word in the filter.
    refute has_element?(live, "#bindings button")
  end

  test "filters by state", ctx do
    active = bind(ctx.tenant, "customer-1", "Dana's iPhone")
    {:ok, waiting} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-2"})

    {:ok, live, html} = live(ctx.conn, ~p"/bindings")
    assert html =~ "2 in total"

    html = live |> form("form[phx-change=filter]", %{"status" => "pending"}) |> render_change()

    assert html =~ "1 in total"
    assert html =~ "/bindings/#{waiting.public_id}"
    refute html =~ "/bindings/#{active.public_id}"
  end

  test "enrolling shows the activation code once, with its deadline", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/bindings")

    live |> element("button", "New binding") |> render_click()

    html =
      live
      |> form("#enrollment-form", binding: %{external_id: "customer-9", name: "Work phone"})
      |> render_submit()

    {:ok, binding} = BindingRepo.get_by_external_id(ctx.tenant, "customer-9")

    assert html =~ "Activation code"
    assert html =~ binding.enroll_token
    assert html =~ "Expires"
    assert html =~ binding.public_id
    assert html =~ "Work phone"
  end

  test "the code is a QR the app can scan, and the payload is what it parses", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/bindings")

    live |> element("button", "New binding") |> render_click()

    html =
      live
      |> form("#enrollment-form", binding: %{external_id: "customer-qr"})
      |> render_submit()

    {:ok, binding} = BindingRepo.get_by_external_id(ctx.tenant, "customer-qr")

    assert html =~ "<svg"
    assert has_element?(live, "#activation-code svg")

    payload = Jason.decode!(ScaWeb.Enrollment.payload(ctx.tenant, binding))

    assert payload["type"] == "sca-proto-enroll"
    assert payload["connect_token"] == binding.enroll_token
    assert payload["nonce"] == binding.enroll_nonce

    # The merchant is part of the address, so every later call carries it.
    assert payload["connect_url"] =~ ~r{^https?://.+/t/#{ctx.tenant.public_id}$}
    assert html =~ ctx.tenant.public_id
  end

  test "the address to type in is shown next to the code", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/bindings")

    live |> element("button", "New binding") |> render_click()

    html =
      live
      |> form("#enrollment-form", binding: %{external_id: "customer-manual"})
      |> render_submit()

    assert html =~ "Server address"
    assert html =~ "/t/#{ctx.tenant.public_id}"
  end

  test "a device still waiting for a scan shows the same QR on its own page", ctx do
    {:ok, binding} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-wait"})

    {:ok, _live, html} = live(ctx.conn, ~p"/bindings/#{binding.public_id}")

    assert html =~ "Waiting for a scan"
    assert html =~ "<svg"
  end

  test "enrolling without a reference is refused in place", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/bindings")

    live |> element("button", "New binding") |> render_click()

    html = live |> form("#enrollment-form", binding: %{external_id: ""}) |> render_submit()

    assert html =~ "can&#39;t be blank"
    refute html =~ "Activation code"
  end

  test "a device from another merchant is not listed", ctx do
    other = Fixtures.merchant()
    stranger = bind(other.tenant, "customer-1", "Someone else's phone")

    {:ok, _live, html} = live(ctx.conn, ~p"/bindings")

    refute html =~ "Someone else&#39;s phone"
    refute html =~ stranger.public_id
  end

  describe "the device screen" do
    test "shows what it is and what it was asked", ctx do
      binding = bind(ctx.tenant, "customer-1", "Dana's iPhone")

      {:ok, _request} =
        Actions.Request.create(binding, %{
          type: :payment,
          title: "Payment confirmation",
          payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
        })

      {:ok, _live, html} = live(ctx.conn, ~p"/bindings/#{binding.public_id}")

      assert html =~ "Dana&#39;s iPhone"
      assert html =~ "customer-1"
      assert html =~ "Payment confirmation"
      assert html =~ "Revoke device"
    end

    test "revoking asks first, then takes the device out of service", ctx do
      binding = bind(ctx.tenant, "customer-1", "Dana's iPhone")

      {:ok, live, _html} = live(ctx.conn, ~p"/bindings/#{binding.public_id}")

      html = live |> element("button", "Revoke device") |> render_click()
      assert html =~ "Revoke this device?"

      html = live |> element("#revoke-binding button", "Revoke device") |> render_click()

      assert html =~ "revoked"
      assert {:ok, %{status: :revoked}} = BindingRepo.get(binding.id)
      refute html =~ "Revoke device"
    end

    test "a pending device still shows its activation code", ctx do
      {:ok, waiting} = Actions.Binding.enroll(ctx.tenant, %{external_id: "customer-2"})

      {:ok, _live, html} = live(ctx.conn, ~p"/bindings/#{waiting.public_id}")

      assert html =~ "Waiting for a scan"
      assert html =~ waiting.enroll_token
    end

    test "another merchant's device is simply not found", ctx do
      other = Fixtures.merchant()
      stranger = bind(other.tenant, "customer-1", "Someone else's phone")

      assert {:error, {:live_redirect, %{to: "/bindings"}}} =
               live(ctx.conn, ~p"/bindings/#{stranger.public_id}")
    end
  end
end
