defmodule Sca.ScopeTest do
  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Scope

  setup do
    tenant = insert(:tenant)
    device = Device.bind(tenant)

    {:ok, request} =
      Actions.Request.create(device.binding, %{
        type: :freeform,
        title: "Confirm",
        payload: %{"note" => "hello"}
      })

    %{scope: Scope.for_tenant(tenant), tenant: tenant, binding: device.binding, request: request}
  end

  test "resolves what belongs to the tenant", ctx do
    assert {:ok, binding} = Scope.fetch_binding(ctx.scope, ctx.binding.public_id)
    assert binding.id == ctx.binding.id

    assert {:ok, request} = Scope.fetch_request(ctx.scope, ctx.request.public_id)
    assert request.id == ctx.request.id

    user = insert(:user, tenant: ctx.tenant)
    assert {:ok, found} = Scope.fetch_user(ctx.scope, user.public_id)
    assert found.id == user.id
  end

  test "another tenant's entity is simply not found", ctx do
    stranger = Scope.for_tenant(insert(:tenant))

    assert Scope.fetch_binding(stranger, ctx.binding.public_id) == {:error, :not_found}
    assert Scope.fetch_request(stranger, ctx.request.public_id) == {:error, :not_found}
  end

  test "an id of the wrong kind is not found either", ctx do
    assert Scope.fetch_binding(ctx.scope, ctx.request.public_id) == {:error, :not_found}
    assert Scope.fetch_request(ctx.scope, "nonsense") == {:error, :not_found}
  end

  test "external ids stay inside the tenant", ctx do
    stranger = Scope.for_tenant(insert(:tenant))

    assert {:ok, _binding} =
             Scope.fetch_binding_by_external_id(ctx.scope, ctx.binding.external_id)

    assert Scope.fetch_binding_by_external_id(stranger, ctx.binding.external_id) ==
             {:error, :not_found}
  end

  test "owns?/2 is the check behind all of it", ctx do
    assert Scope.owns?(ctx.scope, ctx.binding)
    refute Scope.owns?(Scope.for_tenant(insert(:tenant)), ctx.binding)
    refute Scope.owns?(ctx.scope, %{})
  end
end
