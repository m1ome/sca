defmodule ScaWeb.Fixtures do
  @moduledoc "A merchant with a signed-in member, for the console tests."

  alias Sca.Actions

  @password "console-test-password"

  def password, do: @password

  def merchant(attrs \\ %{}) do
    email = "member-#{System.unique_integer([:positive])}@merchant.example.com"

    {:ok, %{tenant: tenant, user: user}} =
      Actions.Tenant.create(Map.merge(%{name: "Northstar Payments", owner_email: email}, attrs))

    {:ok, user} = Actions.Tenant.change_user_password(user, @password)

    %{tenant: tenant, user: user}
  end

  def log_in(conn, user) do
    Phoenix.ConnTest.init_test_session(conn, %{user_id: user.id})
  end
end
