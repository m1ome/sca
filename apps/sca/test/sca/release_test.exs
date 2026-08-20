defmodule Sca.ReleaseTest do
  @moduledoc "Bootstrapping an environment nobody can sign into yet."

  use Sca.DataCase, async: false

  alias Sca.Release
  alias Sca.Repos.AdminRepo

  setup do
    previous = {System.get_env("ADMIN_EMAIL"), System.get_env("ADMIN_PASSWORD")}

    on_exit(fn ->
      case previous do
        {nil, nil} -> System.delete_env("ADMIN_EMAIL") && System.delete_env("ADMIN_PASSWORD")
        {email, password} -> put_credentials(email, password)
      end
    end)

    :ok
  end

  defp put_credentials(email, password) do
    System.put_env("ADMIN_EMAIL", email)
    System.put_env("ADMIN_PASSWORD", password)
  end

  test "creates the first staff account from the environment" do
    put_credentials("owner@enum8.example.com", "bootstrap-password")

    assert :ok = Release.create_first_admin()

    assert {:ok, admin} = AdminRepo.get_by_email("owner@enum8.example.com")
    assert admin.role == :superadmin
    assert admin.status == :active

    # The password is the one that was handed in, not a generated one.
    assert Bcrypt.verify_pass("bootstrap-password", admin.password_hash)
  end

  test "does nothing once anybody can sign in" do
    insert(:admin, email: "someone@enum8.example.com")
    put_credentials("owner@enum8.example.com", "bootstrap-password")

    assert :ok = Release.create_first_admin()
    assert {:error, :not_found} = AdminRepo.get_by_email("owner@enum8.example.com")
  end

  test "without the variables it is a no-op, not a failed deploy" do
    System.delete_env("ADMIN_EMAIL")
    System.delete_env("ADMIN_PASSWORD")

    assert :ok = Release.create_first_admin()
    assert AdminRepo.list_all() == []
  end

  test "a password too short to be one is refused loudly" do
    put_credentials("owner@enum8.example.com", "short")

    assert_raise RuntimeError, ~r/no account could be made/, fn ->
      Release.create_first_admin()
    end

    assert AdminRepo.list_all() == []
  end
end
