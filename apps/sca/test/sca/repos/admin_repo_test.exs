defmodule Sca.Repos.AdminRepoTest do
  @moduledoc """
  Admins are plain records for now — no login, so no action to speak of.
  """

  use Sca.DataCase, async: true

  alias Sca.Repos.AdminRepo

  test "create_admin/1 normalises the email and assigns a public id" do
    assert {:ok, admin} =
             AdminRepo.create(%{
               email: " Staff@Sca.example.com ",
               name: "Staff",
               password: "long enough password"
             })

    assert admin.public_id =~ ~r/\AADM-\d+\z/
    assert admin.email == "staff@sca.example.com"
    assert admin.role == :support
    assert admin.status == :active
  end

  test "emails are unique across the whole system" do
    insert(:admin, email: "staff@sca.example.com")

    assert {:error, changeset} =
             AdminRepo.create(%{email: "staff@sca.example.com", password: "long enough password"})

    assert %{email: ["has already been taken"]} = errors_on(changeset)
  end

  test "rejects a malformed email" do
    assert {:error, changeset} =
             AdminRepo.create(%{email: "staff", password: "long enough password"})

    assert %{email: ["must be an email"]} = errors_on(changeset)
  end

  test "an admin can be disabled without losing the record" do
    admin = insert(:admin)

    assert {:ok, disabled} = AdminRepo.update(admin, %{status: :disabled})
    assert disabled.status == :disabled
  end

  test "track_login/1 stamps the last login" do
    admin = insert(:admin)

    assert {:ok, tracked} = AdminRepo.track_login(admin)
    assert tracked.last_login_at
  end

  test "lookups by email and public id" do
    admin = insert(:admin)

    assert {:ok, found} = AdminRepo.get_by_email(String.upcase(admin.email))
    assert found.id == admin.id
    assert {:ok, ^found} = AdminRepo.get_by_public_id(admin.public_id)
    assert AdminRepo.get_by_public_id("TNT-1") == {:error, :not_found}
  end
end
