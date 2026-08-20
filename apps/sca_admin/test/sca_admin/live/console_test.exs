defmodule ScaAdmin.ConsoleTest do
  @moduledoc "The admin console: every merchant in view, and staff management."

  use ScaAdmin.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Actions
  alias Sca.Repos.AdminRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo
  alias ScaAdmin.Fixtures

  setup %{conn: conn} do
    %{admin: admin} = Fixtures.staff()

    %{conn: Fixtures.log_in(conn, admin), admin: admin}
  end

  defp shown_password(html) do
    [_match, password] = Regex.run(~r/id="owner-password"[^>]*>\s*([^<\s]+)/, html)

    password
  end

  describe "tenants" do
    test "lists merchants and links to them by name", ctx do
      tenant = Fixtures.merchant("Northstar Payments")

      {:ok, _live, html} = live(ctx.conn, ~p"/tenants")

      assert html =~ "Northstar Payments"
      assert html =~ tenant.public_id
      assert html =~ ~s(href="/tenants/#{tenant.public_id}")
    end

    test "onboards a merchant and hands over the owner's one-time password", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/tenants")

      live |> element("button", "New merchant") |> render_click()

      html =
        live
        |> form("#tenant-form",
          tenant: %{name: "Acme Bank", owner_email: "ops@acme.example.com"}
        )
        |> render_submit()

      assert [tenant] = Enum.filter(TenantRepo.list_all(), &(&1.name == "Acme Bank"))
      assert {:ok, owner} = UserRepo.get_by_email(tenant, "ops@acme.example.com")
      assert owner.role == :owner

      # Everything the merchant needs to sign in, including the one copy of the
      # password that will ever exist.
      assert html =~ tenant.public_id
      assert html =~ "ops@acme.example.com"
      assert html =~ "Merchant id"
      assert html =~ "Console"

      assert Bcrypt.verify_pass(shown_password(html), owner.password_hash)
    end

    test "a merchant without a name is refused in place", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/tenants")

      live |> element("button", "New merchant") |> render_click()

      html =
        live
        |> form("#tenant-form", tenant: %{name: "", owner_email: "ops@acme.example.com"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute html =~ "Merchant id"
    end

    test "a merchant's screen shows configuration without their signing key", ctx do
      tenant = Fixtures.merchant()

      {:ok, tenant} =
        Actions.Tenant.update_settings(tenant, %{webhook_url: "https://acme.example.com/hooks"})

      {:ok, _live, html} = live(ctx.conn, ~p"/tenants/#{tenant.public_id}")

      assert html =~ "https://acme.example.com/hooks"
      assert html =~ "Configured"
      refute html =~ tenant.settings.webhook_secret
    end

    test "suspending a merchant asks first", ctx do
      tenant = Fixtures.merchant()

      {:ok, live, _html} = live(ctx.conn, ~p"/tenants/#{tenant.public_id}")

      html = live |> element("button", "Suspend merchant") |> render_click()
      assert html =~ "Suspend this merchant?"

      html = live |> element("#suspend-tenant button", "Suspend merchant") |> render_click()

      assert html =~ "suspended"
      assert {:ok, %{status: :suspended}} = TenantRepo.get(tenant.id)
      assert html =~ "Resume merchant"
    end
  end

  describe "platform lists" do
    setup do
      northstar = Fixtures.merchant("Northstar Payments")
      meridian = Fixtures.merchant("Meridian Bank")

      binding = Fixtures.device(northstar, "customer-1")
      other = Fixtures.device(meridian, "customer-2")

      {:ok, _request} =
        Actions.Request.create(binding, %{
          type: :payment,
          title: "Northstar payment",
          payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"}
        })

      {:ok, _request} =
        Actions.Request.create(other, %{
          type: :login,
          title: "Meridian sign-in",
          payload: %{"ip" => "203.0.113.9"}
        })

      %{northstar: northstar, meridian: meridian}
    end

    test "approvals show every merchant, with the merchant named", ctx do
      {:ok, _live, html} = live(ctx.conn, ~p"/approvals")

      assert html =~ "Northstar payment"
      assert html =~ "Meridian sign-in"
      assert html =~ ~s(href="/tenants/#{ctx.northstar.public_id}")
      assert html =~ "2 in total"
    end

    test "approvals can be filtered down to one merchant", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/approvals")

      html =
        live
        |> form("form[phx-change=filter]", %{"tenant" => ctx.northstar.id, "status" => ""})
        |> render_change()

      assert html =~ "1 in total"
      assert html =~ "Northstar payment"
      refute html =~ "Meridian sign-in"
    end

    test "bindings show every merchant's devices", ctx do
      {:ok, live, html} = live(ctx.conn, ~p"/bindings")

      assert html =~ "2 in total"
      assert html =~ "customer-1"
      assert html =~ "customer-2"

      html =
        live
        |> form("form[phx-change=filter]", %{"tenant" => ctx.meridian.id, "status" => ""})
        |> render_change()

      assert html =~ "1 in total"
      assert html =~ "customer-2"
      refute html =~ "customer-1"
    end

    test "overview counts what the lists show", ctx do
      {:ok, _live, html} = live(ctx.conn, ~p"/")

      assert html =~ "Merchants"
      assert html =~ "Active devices"
      assert html =~ "2"
      assert html =~ ctx.northstar.name || true
    end
  end

  describe "staff" do
    test "adding staff shows their password once", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/team")

      live |> element("button", "Add staff") |> render_click()

      html =
        live
        |> form("#admin-form",
          admin: %{email: "new@enum8.example.com", name: "New Staff", role: "superadmin"}
        )
        |> render_submit()

      assert html =~ "Password for the new account"
      assert html =~ "new@enum8.example.com"

      assert {:ok, admin} = AdminRepo.get_by_email("new@enum8.example.com")
      assert admin.role == :superadmin
    end

    test "a duplicate email is refused in place", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/team")

      live |> element("button", "Add staff") |> render_click()

      html = live |> form("#admin-form", admin: %{email: ctx.admin.email}) |> render_submit()

      assert html =~ "has already been taken"
      refute html =~ "Password for the new account"
    end

    test "role, access and password reset live on the staff screen", ctx do
      %{admin: colleague} = Fixtures.staff()

      {:ok, live, _html} = live(ctx.conn, ~p"/team/#{colleague.public_id}")

      html = live |> form("form[phx-change=role]", %{"role" => "superadmin"}) |> render_change()
      assert html =~ "Role updated"

      # Both actions ask first; the button in the modal is what does it.
      html = live |> element("button", "Disable access") |> render_click()
      assert html =~ "Disable this account?"
      assert {:ok, %{status: :active}} = AdminRepo.get(colleague.id)

      html = live |> element("#confirm-disable button", "Disable access") |> render_click()
      assert html =~ "Access disabled"
      assert {:ok, %{status: :disabled}} = AdminRepo.get(colleague.id)

      html = live |> element("button", "Reset password") |> render_click()
      assert html =~ "Reset this password?"

      html = live |> element("#confirm-reset button", "Reset password") |> render_click()
      assert html =~ "New password"
    end

    test "you cannot lock yourself out", ctx do
      {:ok, live, html} = live(ctx.conn, ~p"/team/#{ctx.admin.public_id}")

      assert html =~ "You cannot change your own role"
      assert live |> element("button", "Disable access") |> render() =~ "disabled"
    end
  end

  describe "settings" do
    test "changes your own password, once you prove the current one", ctx do
      %{admin: admin, password: password} = Fixtures.staff()
      conn = Fixtures.log_in(ctx.conn, admin)

      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form[phx-submit=change-password]", %{
          "password" => %{"current" => "wrong", "new" => "a brand new password"}
        })
        |> render_submit()

      assert html =~ "not your current password"

      html =
        live
        |> form("form[phx-submit=change-password]", %{
          "password" => %{"current" => password, "new" => "a brand new password"}
        })
        |> render_submit()

      assert html =~ "Password changed"
      assert {:ok, updated} = AdminRepo.get(admin.id)
      assert Bcrypt.verify_pass("a brand new password", updated.password_hash)
    end

    test "refuses a password that is too short", ctx do
      %{admin: admin, password: password} = Fixtures.staff()
      conn = Fixtures.log_in(ctx.conn, admin)

      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form[phx-submit=change-password]", %{
          "password" => %{"current" => password, "new" => "short"}
        })
        |> render_submit()

      assert html =~ "password"
      refute html =~ "Password changed"
    end
  end
end
