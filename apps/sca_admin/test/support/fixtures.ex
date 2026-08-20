defmodule ScaAdmin.Fixtures do
  @moduledoc "A staff account, and merchants for it to look at."

  alias Sca.Actions

  def staff(attrs \\ %{}) do
    email = "staff-#{System.unique_integer([:positive])}@enum8.example.com"

    {:ok, %{admin: admin, password: password}} =
      Actions.Admin.create(Map.merge(%{email: email, name: "Sam Support"}, attrs))

    %{admin: admin, password: password}
  end

  def merchant(name \\ "Northstar Payments") do
    {:ok, %{tenant: tenant}} =
      Actions.Tenant.create(%{
        name: name,
        owner_email: "ops-#{System.unique_integer([:positive])}@merchant.example.com"
      })

    tenant
  end

  def device(tenant, external_id \\ "customer-1") do
    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: external_id})

    {:ok, %{binding: binding}} =
      Actions.Binding.bind(pending.enroll_token, %{
        public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0)),
        name: "Dana's iPhone",
        push_platform: :ios
      })

    binding
  end

  def log_in(conn, admin), do: Phoenix.ConnTest.init_test_session(conn, %{admin_id: admin.id})
end
