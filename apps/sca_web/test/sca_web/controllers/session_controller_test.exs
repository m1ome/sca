defmodule ScaWeb.SessionControllerTest do
  use ScaWeb.ConnCase, async: true

  alias Sca.Actions
  alias ScaWeb.Fixtures

  setup do
    Map.put(Fixtures.merchant(), :password, Fixtures.password())
  end

  test "the login screen asks for merchant, email and password", %{conn: conn} do
    html = conn |> get(~p"/log-in") |> html_response(200)

    assert html =~ "Sign in to Enum8"
    assert html =~ "Merchant ID"
    assert html =~ "session[email]"
  end

  test "signing in lands on the console", ctx do
    conn = post(ctx.conn, ~p"/log-in", session: credentials(ctx))

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_id) == ctx.user.id
  end

  test "a wrong password says nothing useful", ctx do
    conn = post(ctx.conn, ~p"/log-in", session: %{credentials(ctx) | "password" => "nope"})

    assert html_response(conn, 401) =~ "do not match an account"
    refute get_session(conn, :user_id)
  end

  test "the right password in the wrong merchant is still wrong", ctx do
    other = Fixtures.merchant()

    conn =
      post(ctx.conn, ~p"/log-in",
        session: %{credentials(ctx) | "tenant" => other.tenant.public_id}
      )

    assert html_response(conn, 401) =~ "do not match an account"
  end

  test "a disabled member cannot sign in", ctx do
    {:ok, _user} = Actions.Tenant.disable_user(ctx.user)

    conn = post(ctx.conn, ~p"/log-in", session: credentials(ctx))

    assert html_response(conn, 401) =~ "disabled"
  end

  test "signing out clears the session", ctx do
    conn =
      ctx.conn
      |> Fixtures.log_in(ctx.user)
      |> delete(~p"/log-out")

    assert redirected_to(conn) == ~p"/log-in"
    refute get_session(conn, :user_id)
  end

  test "the console is closed to strangers", %{conn: conn} do
    conn = get(conn, ~p"/approvals")

    assert redirected_to(conn) == ~p"/log-in"
  end

  defp credentials(ctx) do
    %{
      "tenant" => ctx.tenant.public_id,
      "email" => ctx.user.email,
      "password" => ctx.password
    }
  end
end
