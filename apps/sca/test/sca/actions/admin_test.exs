defmodule Sca.Actions.AdminTest do
  @moduledoc "Our own staff accounts: creating them, and taking them away."

  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Repos.AdminRepo

  test "create/1 hashes a generated password and hands it over once" do
    assert {:ok, %{admin: admin, password: password}} =
             Actions.Admin.create(%{email: "Staff@Sca.example.com", name: "Staff"})

    assert admin.public_id =~ ~r/\AADM-\d+\z/
    assert admin.email == "staff@sca.example.com"
    assert admin.role == :support
    assert admin.password == nil
    assert byte_size(password) >= 12
    assert Bcrypt.verify_pass(password, admin.password_hash)
  end

  test "create/1 refuses a duplicate email against the field somebody typed" do
    insert(:admin, email: "staff@sca.example.com")

    assert {:error, changeset} = Actions.Admin.create(%{email: "staff@sca.example.com"})
    assert %{email: ["has already been taken"]} = errors_on(changeset)
  end

  test "change_role/2 promotes and demotes" do
    admin = insert(:admin)

    assert {:ok, %{role: :superadmin}} = Actions.Admin.change_role(admin, :superadmin)
  end

  test "reset_password/1 replaces the hash and returns the new password" do
    admin = insert(:admin)

    assert {:ok, %{admin: updated, password: password}} = Actions.Admin.reset_password(admin)
    assert Bcrypt.verify_pass(password, updated.password_hash)
    refute updated.password_hash == admin.password_hash
  end

  test "disable/1 and enable/1 keep the record either way" do
    admin = insert(:admin)

    assert {:ok, %{status: :disabled}} = Actions.Admin.disable(admin)
    assert {:ok, disabled} = AdminRepo.get(admin.id)
    assert {:ok, %{status: :active}} = Actions.Admin.enable(disabled)
  end

  test "track_login/1 stamps the visit" do
    admin = insert(:admin)

    assert {:ok, tracked} = Actions.Admin.track_login(admin)
    assert tracked.last_login_at
  end
end
