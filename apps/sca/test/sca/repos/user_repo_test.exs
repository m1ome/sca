defmodule Sca.Repos.UserRepoTest do
  use Sca.DataCase, async: true

  alias Sca.Repos.UserRepo

  setup do
    %{tenant: insert(:tenant)}
  end

  test "list/1 is scoped to the tenant", %{tenant: tenant} do
    user = insert(:user, tenant: tenant)
    insert(:user)

    assert Enum.map(UserRepo.list_by_tenant(tenant), & &1.id) == [user.id]
  end

  test "get_by_email/2 normalises what it is given", %{tenant: tenant} do
    user = insert(:user, tenant: tenant, email: "member@merchant.example.com")

    assert {:ok, found} = UserRepo.get_by_email(tenant, " Member@Merchant.example.com ")
    assert found.id == user.id
  end

  test "get_by_email/2 does not cross tenants", %{tenant: tenant} do
    user = insert(:user)

    assert UserRepo.get_by_email(tenant, user.email) == {:error, :not_found}
  end

  test "get_by_public_id/1 refuses ids of other entities", %{tenant: tenant} do
    user = insert(:user, tenant: tenant)

    assert {:ok, found} = UserRepo.get_by_public_id(user.public_id)
    assert found.id == user.id
    assert UserRepo.get_by_public_id(tenant.public_id) == {:error, :not_found}
  end
end
