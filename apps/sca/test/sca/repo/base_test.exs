defmodule Sca.Repo.BaseTest do
  @moduledoc """
  What every repository inherits: the CRUD shape, `{:ok, _} | {:error, :not_found}`
  lookups, the public-id guard and Flop listing.
  """

  use Sca.DataCase, async: true

  alias Sca.Repos.AdminRepo
  alias Sca.Repos.TenantRepo

  describe "the inherited CRUD" do
    test "create/1 and update/2 go through the model's changeset" do
      assert {:ok, admin} =
               AdminRepo.create(%{
                 email: "Staff@Sca.example.com",
                 name: "Staff",
                 password: "long enough password"
               })

      assert admin.email == "staff@sca.example.com"

      assert {:ok, updated} = AdminRepo.update(admin, %{name: "Renamed"})
      assert updated.name == "Renamed"

      assert {:error, changeset} =
               AdminRepo.create(%{email: "nope", password: "long enough password"})

      assert %{email: ["must be an email"]} = errors_on(changeset)
    end

    test "change/2 writes fields the schema does not validate" do
      admin = insert(:admin)

      assert {:ok, tracked} = AdminRepo.change(admin, last_login_at: Timex.now())
      assert tracked.last_login_at
    end

    test "get/1 answers with a tuple rather than nil" do
      admin = insert(:admin)

      assert {:ok, found} = AdminRepo.get(admin.id)
      assert found.id == admin.id
      assert AdminRepo.get(Ecto.UUID.generate()) == {:error, :not_found}
      assert AdminRepo.get!(admin.id).id == admin.id
    end

    test "get_by/1 takes plain clauses" do
      admin = insert(:admin)

      assert {:ok, found} = AdminRepo.get_by(email: admin.email)
      assert found.id == admin.id
      assert AdminRepo.get_by(email: "nobody@example.com") == {:error, :not_found}
    end

    test "delete/1 removes the row" do
      admin = insert(:admin)

      assert {:ok, _admin} = AdminRepo.delete(admin)
      assert AdminRepo.get(admin.id) == {:error, :not_found}
    end
  end

  describe "get_by_public_id/1" do
    test "finds the record it belongs to" do
      tenant = insert(:tenant)

      assert {:ok, found} = TenantRepo.get_by_public_id(tenant.public_id)
      assert found.id == tenant.id
    end

    test "refuses an id that belongs to another entity, without touching the database" do
      binding = insert(:binding)

      assert TenantRepo.get_by_public_id(binding.public_id) == {:error, :not_found}
      assert TenantRepo.get_by_public_id("nonsense") == {:error, :not_found}
    end
  end

  describe "list/1 through Flop" do
    setup do
      %{
        acme: insert(:tenant, name: "ACME Bank"),
        globex: insert(:tenant, name: "Globex"),
        initech: insert(:tenant, name: "Initech", status: :suspended)
      }
    end

    test "returns records with pagination metadata", ctx do
      assert {tenants, %Flop.Meta{} = meta} = TenantRepo.list()

      assert length(tenants) == 3
      assert meta.total_count == 3
      assert ctx.acme.id in Enum.map(tenants, & &1.id)
    end

    test "filters by what the model declares filterable", ctx do
      params = %{filters: [%{field: :status, op: :==, value: :suspended}]}

      assert {[tenant], _meta} = TenantRepo.list(params)
      assert tenant.id == ctx.initech.id
    end

    test "sorts and paginates", ctx do
      params = %{order_by: [:name], order_directions: [:asc], page: 1, page_size: 2}

      assert {[first, second], meta} = TenantRepo.list(params)
      assert [first.id, second.id] == [ctx.acme.id, ctx.globex.id]
      assert meta.has_next_page?
    end

    test "refuses to sort by a field the model did not open up" do
      assert_raise Flop.InvalidParamsError, fn ->
        TenantRepo.list(%{order_by: [:settings]})
      end
    end
  end
end
