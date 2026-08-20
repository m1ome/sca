defmodule ScaWeb.AccountLiveTest do
  @moduledoc "Changing your own password, as opposed to having it reset for you."

  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Repos.UserRepo
  alias ScaWeb.Auth
  alias ScaWeb.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()

    %{conn: Fixtures.log_in(conn, user), tenant: tenant, user: user}
  end

  defp change(live, current, new) do
    live
    |> form("form[phx-submit=change-password]", %{
      "password" => %{"current" => current, "new" => new}
    })
    |> render_submit()
  end

  test "shows who you are signed in as", ctx do
    {:ok, _live, html} = live(ctx.conn, ~p"/account")

    assert html =~ ctx.user.email
    assert html =~ ctx.user.public_id
    assert html =~ ctx.tenant.public_id
  end

  test "the header links here", ctx do
    {:ok, _live, html} = live(ctx.conn, ~p"/bindings")

    assert html =~ ~s(href="/account")
  end

  test "changing the password needs the current one", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/account")

    html = change(live, "not-my-password", "a-brand-new-password")

    assert html =~ "not your current password"

    # The old one still works, so nothing was changed on a wrong guess.
    assert {:ok, _user} =
             Auth.authenticate(ctx.tenant.public_id, ctx.user.email, Fixtures.password())
  end

  test "with the current one it changes, and the old one stops working", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/account")

    html = change(live, Fixtures.password(), "a-brand-new-password")

    assert html =~ "Password changed"

    assert {:ok, _user} =
             Auth.authenticate(ctx.tenant.public_id, ctx.user.email, "a-brand-new-password")

    assert {:error, :invalid_credentials} =
             Auth.authenticate(ctx.tenant.public_id, ctx.user.email, Fixtures.password())
  end

  test "a password too short to be one is refused with the reason", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/account")

    html = change(live, Fixtures.password(), "short")

    assert html =~ "at least 12"
    assert {:ok, user} = UserRepo.get(ctx.user.id)
    assert user.password_hash == ctx.user.password_hash
  end
end
