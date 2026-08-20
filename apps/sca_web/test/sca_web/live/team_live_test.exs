defmodule ScaWeb.TeamLiveTest do
  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Actions
  alias Sca.Repos.UserRepo
  alias ScaWeb.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()

    %{conn: Fixtures.log_in(conn, user), tenant: tenant, owner: user}
  end

  test "lists the team without acting on anyone", ctx do
    {:ok, live, html} = live(ctx.conn, ~p"/team")

    assert html =~ ctx.owner.email
    assert html =~ "Owner"
    assert html =~ "active"
    assert html =~ "/team/#{ctx.owner.public_id}"
    refute has_element?(live, "#members button")
  end

  test "adding a member shows their password once", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/team")

    live |> element("button", "Add member") |> render_click()

    html =
      live
      |> form("#member-form",
        user: %{email: "new@merchant.example.com", name: "New Person", role: "viewer"}
      )
      |> render_submit()

    assert html =~ "Password for the new member"
    assert html =~ "new@merchant.example.com"
    assert html =~ "New Person"

    assert {:ok, member} = UserRepo.get_by_email(ctx.tenant, "new@merchant.example.com")
    assert member.role == :viewer

    [_prefix, shown] = String.split(html, ~s(id="member-password"), parts: 2)

    password =
      shown
      |> String.split(">", parts: 2)
      |> List.last()
      |> String.split("<")
      |> hd()
      |> String.trim()

    assert Bcrypt.verify_pass(password, member.password_hash)
  end

  test "a duplicate email is refused in place", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/team")

    live |> element("button", "Add member") |> render_click()

    html = live |> form("#member-form", user: %{email: ctx.owner.email}) |> render_submit()

    assert html =~ "has already been taken"
    refute html =~ "Password for the new member"
  end

  test "another merchant's team is not listed", ctx do
    other = Fixtures.merchant()

    {:ok, _live, html} = live(ctx.conn, ~p"/team")

    refute html =~ other.user.email
  end

  describe "the member screen" do
    setup ctx do
      {:ok, %{user: member}} =
        Actions.Tenant.add_user(ctx.tenant, %{email: "member@merchant.example.com", role: :viewer})

      Map.put(ctx, :member, member)
    end

    test "changes a role", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/team/#{ctx.member.public_id}")

      html = live |> form("form[phx-change=role]", %{"role" => "admin"}) |> render_change()

      assert html =~ "Role updated"
      assert {:ok, %{role: :admin}} = UserRepo.get(ctx.member.id)
    end

    test "disables and re-enables access, asking first", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/team/#{ctx.member.public_id}")

      # The button offers; the modal is what actually does it.
      html = live |> element("button", "Disable access") |> render_click()
      assert html =~ "Disable this member?"
      assert {:ok, %{status: :active}} = UserRepo.get(ctx.member.id)

      html = live |> element("#confirm-disable button", "Disable access") |> render_click()
      assert html =~ "Member disabled"
      assert {:ok, %{status: :disabled}} = UserRepo.get(ctx.member.id)

      html = live |> element("button", "Enable access") |> render_click()
      assert html =~ "can sign in again"
      assert {:ok, %{status: :active}} = UserRepo.get(ctx.member.id)
    end

    test "resets a password and shows the new one once, asking first", ctx do
      {:ok, live, _html} = live(ctx.conn, ~p"/team/#{ctx.member.public_id}")

      html = live |> element("button", "Reset password") |> render_click()
      assert html =~ "Reset this password?"

      html = live |> element("#confirm-reset button", "Reset password") |> render_click()

      assert html =~ "New password"
      assert html =~ "reset-password-value"
    end

    test "you cannot lock yourself out", ctx do
      {:ok, live, html} = live(ctx.conn, ~p"/team/#{ctx.owner.public_id}")

      assert html =~ "You cannot change your own role"
      assert live |> element("button", "Disable access") |> render() =~ "disabled"
    end

    test "another merchant's member is simply not found", ctx do
      other = Fixtures.merchant()

      assert {:error, {:live_redirect, %{to: "/team"}}} =
               live(ctx.conn, ~p"/team/#{other.user.public_id}")
    end
  end
end
