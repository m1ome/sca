defmodule ScaAdmin.SessionControllerTest do
  use ScaAdmin.ConnCase, async: true

  alias Sca.Actions
  alias Sca.Repos.AdminRepo
  alias ScaAdmin.Fixtures

  setup do
    Fixtures.staff()
  end

  test "the login screen asks for email and password only", %{conn: conn} do
    html = conn |> get(~p"/log-in") |> html_response(200)

    assert html =~ "Enum8 admin console"
    assert html =~ "session[email]"
    refute html =~ "Merchant ID"
  end

  test "signing in lands on the console and stamps the visit", ctx do
    conn = post(ctx.conn, ~p"/log-in", session: %{email: ctx.admin.email, password: ctx.password})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :admin_id) == ctx.admin.id
    assert {:ok, %{last_login_at: %DateTime{}}} = AdminRepo.get(ctx.admin.id)
  end

  test "a wrong password says nothing useful", ctx do
    conn = post(ctx.conn, ~p"/log-in", session: %{email: ctx.admin.email, password: "nope"})

    assert html_response(conn, 401) =~ "do not match an account"
    refute get_session(conn, :admin_id)
  end

  test "a disabled account cannot sign in", ctx do
    {:ok, _admin} = Actions.Admin.disable(ctx.admin)

    conn = post(ctx.conn, ~p"/log-in", session: %{email: ctx.admin.email, password: ctx.password})

    assert html_response(conn, 401) =~ "disabled"
  end

  test "a merchant's password is no good here", ctx do
    tenant = Fixtures.merchant()

    {:ok, %{user: user, password: password}} =
      Actions.Tenant.add_user(tenant, %{email: "ops@merchant.example.com"})

    conn = post(ctx.conn, ~p"/log-in", session: %{email: user.email, password: password})

    assert html_response(conn, 401) =~ "do not match an account"
  end

  test "signing out clears the session", ctx do
    conn = ctx.conn |> Fixtures.log_in(ctx.admin) |> delete(~p"/log-out")

    assert redirected_to(conn) == ~p"/log-in"
    refute get_session(conn, :admin_id)
  end

  test "the console is closed to strangers", %{conn: conn} do
    assert conn |> get(~p"/tenants") |> redirected_to() == ~p"/log-in"
  end
end
