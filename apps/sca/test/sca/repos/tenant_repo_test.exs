defmodule Sca.Repos.TenantRepoTest do
  use Sca.DataCase, async: true

  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo

  test "a tenant can be suspended and brought back without losing anything" do
    tenant = insert(:tenant)
    insert(:user, tenant: tenant)

    assert {:ok, suspended} = TenantRepo.update(tenant, %{status: :suspended})
    assert suspended.status == :suspended
    assert {:ok, active} = TenantRepo.update(suspended, %{status: :active})
    assert active.status == :active
    assert length(UserRepo.list_by_tenant(tenant)) == 1
  end

  test "deleting a tenant takes its users, bindings and requests with it" do
    tenant = insert(:tenant)
    insert(:user, tenant: tenant)
    binding = insert(:active_binding, tenant: tenant)
    insert(:request, tenant: tenant, binding: binding)

    assert {:ok, _tenant} = TenantRepo.delete(tenant)
    assert UserRepo.list_by_tenant(tenant) == []
    assert BindingRepo.list_by_tenant(tenant) == []
    assert RequestRepo.list_by_tenant(tenant) == []
  end

  test "list/0 returns tenants oldest first" do
    one = insert(:tenant)
    two = insert(:tenant)

    assert Enum.map(TenantRepo.list_all(), & &1.id) == [one.id, two.id]
  end
end
