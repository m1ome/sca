defmodule Sca.Actions.TenantTest do
  @moduledoc """
  Onboarding a merchant, turning them off, and managing the team inside.
  """

  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Models
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo

  @certificate File.read!(Path.expand("../../support/fixtures/webhook_cert.pem", __DIR__))

  describe "create/1" do
    test "creates the tenant and its first member in one go" do
      assert {:ok, %{tenant: tenant, user: user, password: password}} =
               Actions.Tenant.create(%{
                 name: "ACME Bank",
                 owner_email: "Ops@ACME.example.com",
                 owner_name: "Ops"
               })

      assert tenant.name == "ACME Bank"
      assert tenant.status == :active
      assert tenant.public_id =~ ~r/\ATNT-\d+\z/
      assert tenant.settings.default_request_timeout_seconds == 300

      assert user.tenant_id == tenant.id
      assert user.email == "ops@acme.example.com"
      assert user.role == :owner
      assert user.public_id =~ ~r/\AUSR-\d+\z/

      assert byte_size(password) >= 12
      assert user.password == nil
      assert Bcrypt.verify_pass(password, user.password_hash)
    end

    test "every tenant is born with a webhook signing secret" do
      {:ok, %{tenant: tenant}} = Actions.Tenant.create(owner_attrs(%{name: "ACME Bank"}))

      assert byte_size(tenant.settings.webhook_secret) > 20
    end

    test "a secret the caller supplied is kept" do
      {:ok, %{tenant: tenant}} =
        Actions.Tenant.create(
          owner_attrs(%{name: "ACME Bank", settings: %{webhook_secret: "ours-to-keep"}})
        )

      assert tenant.settings.webhook_secret == "ours-to-keep"
    end

    test "a tenant without a usable owner is not created at all" do
      assert {:error, changeset} =
               Actions.Tenant.create(%{name: "ACME Bank", owner_email: "not-an-email"})

      assert %{email: ["must be an email"]} = errors_on(changeset)
      assert TenantRepo.list_all() == []
    end

    test "requires a name" do
      assert {:error, changeset} = Actions.Tenant.create(owner_attrs(%{}))
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "add_user/2" do
    setup do
      %{tenant: insert(:tenant)}
    end

    test "generates a password when the caller has none", %{tenant: tenant} do
      assert {:ok, %{user: user, password: password}} =
               Actions.Tenant.add_user(tenant, %{email: "member@acme.example.com", role: :admin})

      assert user.role == :admin
      assert is_binary(password)
      assert Bcrypt.verify_pass(password, user.password_hash)
    end

    test "keeps the password the caller chose", %{tenant: tenant} do
      assert {:ok, %{user: user, password: nil}} =
               Actions.Tenant.add_user(tenant, %{
                 email: "member@acme.example.com",
                 password: "a long enough password"
               })

      assert Bcrypt.verify_pass("a long enough password", user.password_hash)
    end

    test "rejects a short password", %{tenant: tenant} do
      assert {:error, changeset} =
               Actions.Tenant.add_user(tenant, %{email: "a@acme.example.com", password: "short"})

      assert %{password: [_message]} = errors_on(changeset)
    end

    test "the same email can exist in two tenants but not twice in one", %{tenant: tenant} do
      attrs = %{email: "shared@acme.example.com"}

      assert {:ok, _added} = Actions.Tenant.add_user(tenant, attrs)
      assert {:ok, _added} = Actions.Tenant.add_user(insert(:tenant), attrs)
      assert {:error, changeset} = Actions.Tenant.add_user(tenant, attrs)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  test "change_user_password/2 replaces the hash" do
    user = insert(:user)

    assert {:ok, updated} = Actions.Tenant.change_user_password(user, "another long password")
    refute Bcrypt.verify_pass(Sca.Factory.valid_password(), updated.password_hash)
    assert Bcrypt.verify_pass("another long password", updated.password_hash)
  end

  test "disable_user/1 keeps the member and their trail" do
    user = insert(:user)

    assert {:ok, disabled} = Actions.Tenant.disable_user(user)
    assert disabled.status == :disabled
    assert {:ok, _user} = UserRepo.get(user.id)
  end

  describe "deactivate/1" do
    test "stops serving the tenant without touching anything it owns" do
      tenant = insert(:tenant)
      insert(:user, tenant: tenant)
      device = Device.bind(tenant)

      assert {:ok, suspended} = Actions.Tenant.deactivate(tenant)
      assert suspended.status == :suspended
      assert length(UserRepo.list_by_tenant(tenant)) == 1
      assert {:ok, binding} = Sca.Repos.BindingRepo.get(device.binding.id)
      assert binding.status == :active

      assert {:ok, active} = Actions.Tenant.activate(suspended)
      assert active.status == :active
    end
  end

  describe "update_settings/2" do
    test "settings survive a round-trip through jsonb" do
      {:ok, %{tenant: tenant}} = Actions.Tenant.create(owner_attrs(%{name: "ACME Bank"}))

      {:ok, _tenant} =
        Actions.Tenant.update_settings(tenant, %{
          webhook_url: "https://acme.example.com/hooks/sca",
          webhook_certificate: @certificate,
          logo_url: "https://acme.example.com/logo.svg",
          default_request_timeout_seconds: 120
        })

      {:ok, reloaded} = TenantRepo.get(tenant.id)

      assert %Models.Embed.TenantSettings{} = reloaded.settings
      assert reloaded.settings.webhook_url == "https://acme.example.com/hooks/sca"
      assert reloaded.settings.webhook_certificate =~ "BEGIN CERTIFICATE"
      assert reloaded.settings.logo_url == "https://acme.example.com/logo.svg"
      assert reloaded.settings.default_request_timeout_seconds == 120
    end

    test "leaves untouched settings alone" do
      tenant = insert(:tenant)

      assert {:ok, updated} =
               Actions.Tenant.update_settings(tenant, %{default_request_timeout_seconds: 60})

      assert updated.settings.default_request_timeout_seconds == 60
      assert updated.settings.webhook_url == tenant.settings.webhook_url
      assert updated.settings.webhook_secret == tenant.settings.webhook_secret
    end

    test "refuses a certificate we could not encrypt for, where it is pasted" do
      tenant = insert(:tenant)

      assert {:error, changeset} =
               Actions.Tenant.update_settings(tenant, %{
                 webhook_certificate:
                   "-----BEGIN CERTIFICATE-----\ngarbage\n-----END CERTIFICATE-----"
               })

      assert %{settings: [message]} = errors_on(changeset)
      assert message =~ "webhook_certificate"
    end

    test "rejects a non-http webhook url" do
      tenant = insert(:tenant)

      assert {:error, changeset} =
               Actions.Tenant.update_settings(tenant, %{webhook_url: "ftp://acme.example.com"})

      assert %{settings: %{webhook_url: ["must be an http(s) url"]}} = errors_on(changeset)
    end

    test "rejects an absurd request timeout" do
      tenant = insert(:tenant)

      assert {:error, changeset} =
               Actions.Tenant.update_settings(tenant, %{default_request_timeout_seconds: 5})

      assert %{settings: %{default_request_timeout_seconds: [_message]}} = errors_on(changeset)
    end
  end

  test "rotate_webhook_secret/1 replaces the secret and keeps the rest" do
    tenant = insert(:tenant)

    assert {:ok, rotated} = Actions.Tenant.rotate_webhook_secret(tenant)
    refute rotated.settings.webhook_secret == tenant.settings.webhook_secret
    assert rotated.settings.webhook_url == tenant.settings.webhook_url
  end

  defp owner_attrs(attrs), do: Map.put_new(attrs, :owner_email, "ops@acme.example.com")
end
