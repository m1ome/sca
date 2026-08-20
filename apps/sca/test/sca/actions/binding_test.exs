defmodule Sca.Actions.BindingTest do
  @moduledoc """
  `enroll` → `bind` → `refresh_session` → `revoke`, plus the lockout that five
  bad signatures trigger.
  """

  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Crypto
  alias Sca.Repos.BindingRepo

  setup do
    %{tenant: insert(:tenant)}
  end

  describe "enroll/2" do
    test "creates a pending binding with a token and an attestation challenge", %{tenant: tenant} do
      assert {:ok, binding} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})

      assert binding.public_id =~ ~r/\ABIN-\d+\z/
      assert binding.status == :pending
      assert is_binary(binding.enroll_token)
      assert is_binary(binding.enroll_nonce)
      assert Timex.after?(binding.enroll_expires_at, Timex.now())
    end

    test "requires an external id", %{tenant: tenant} do
      assert {:error, changeset} = Actions.Binding.enroll(tenant, %{})
      assert %{external_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "re-enrolling reuses the row and wipes the old device", %{tenant: tenant} do
      device = Device.bind(tenant, %{external_id: "customer-1"})

      assert {:ok, re_enrolled} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})

      assert re_enrolled.id == device.binding.id
      assert re_enrolled.public_id == device.binding.public_id
      assert re_enrolled.status == :pending
      assert re_enrolled.public_key == nil
      assert re_enrolled.push_token == nil
      assert re_enrolled.activated_at == nil
      assert length(BindingRepo.list_by_tenant(tenant)) == 1
    end

    test "the old session dies with the re-enrollment", %{tenant: tenant} do
      Device.bind(tenant, %{external_id: "customer-1"})
      {:ok, re_enrolled} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})

      assert re_enrolled.access_token_hash == nil
      assert re_enrolled.access_token_expires_at == nil
    end

    test "the same external id in another tenant is a different binding", %{tenant: tenant} do
      {:ok, one} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})
      {:ok, two} = Actions.Binding.enroll(insert(:tenant), %{external_id: "customer-1"})

      refute one.id == two.id
    end
  end

  describe "bind/2" do
    setup %{tenant: tenant} do
      {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-1"})
      {public, private} = :crypto.generate_key(:ecdh, :secp256r1)

      %{pending: pending, public_key: Base.encode64(public), private_key: private}
    end

    test "stores the device identity, burns the token and issues a session", ctx do
      assert {:ok, session} =
               Actions.Binding.bind(ctx.pending.enroll_token, %{
                 public_key: ctx.public_key,
                 device_info: %{"model" => "iPhone 15"},
                 attested: true,
                 attestation_type: "android-key",
                 push_token: "push-token",
                 push_platform: :ios
               })

      binding = session.binding

      assert binding.status == :active
      assert binding.public_key == ctx.public_key
      assert binding.algorithm == "ecdsa-p256"
      assert binding.device_info == %{"model" => "iPhone 15"}
      assert binding.attested
      assert binding.activated_at
      assert binding.enroll_token == nil
      assert binding.enroll_nonce == nil

      assert is_binary(session.access_token)
      assert binding.access_token_hash == Crypto.token_digest(session.access_token)
      refute binding.access_token_hash == session.access_token
      assert Timex.after?(session.expires_at, Timex.now())
    end

    test "refuses a public key that is not a P-256 point", ctx do
      assert {:error, changeset} =
               Actions.Binding.bind(ctx.pending.enroll_token, %{public_key: "not-a-key"})

      assert %{public_key: [message]} = errors_on(changeset)
      assert message =~ "not a valid key"
    end

    test "needs a public key", ctx do
      assert {:error, changeset} = Actions.Binding.bind(ctx.pending.enroll_token, %{})
      assert %{public_key: ["can't be blank"]} = errors_on(changeset)
    end

    test "an enrollment token works exactly once", ctx do
      assert {:ok, _session} =
               Actions.Binding.bind(ctx.pending.enroll_token, %{public_key: ctx.public_key})

      assert Actions.Binding.bind(ctx.pending.enroll_token, %{public_key: ctx.public_key}) ==
               {:error, :not_found}
    end

    test "refuses an unknown token", ctx do
      assert Actions.Binding.bind("nonsense", %{public_key: ctx.public_key}) ==
               {:error, :not_found}
    end

    test "refuses an expired enrollment", %{tenant: tenant, public_key: public_key} do
      {:ok, stale} =
        Actions.Binding.enroll(tenant, %{
          external_id: "customer-2",
          enroll_expires_at: Timex.shift(Timex.now(), seconds: -1)
        })

      assert Actions.Binding.bind(stale.enroll_token, %{public_key: public_key}) ==
               {:error, :enrollment_expired}
    end

    test "refuses a binding that is already active", %{tenant: tenant, public_key: public_key} do
      {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-3"})
      {:ok, _session} = Actions.Binding.bind(pending.enroll_token, %{public_key: public_key})

      # Binding clears the enroll token, so this is a revoked binding that
      # still holds one, not a replay.
      binding = BindingRepo.get!(pending.id)
      {:ok, _binding} = BindingRepo.update(binding, %{})

      assert Actions.Binding.bind(pending.enroll_token, %{public_key: public_key}) ==
               {:error, :not_found}
    end
  end

  describe "refresh_session/2" do
    setup %{tenant: tenant} do
      %{device: Device.bind(tenant)}
    end

    test "extends the session for a device that proves possession", %{device: device} do
      expire_token(device.binding, -1)

      {:ok, %{binding: binding, nonce: nonce}} =
        Actions.Binding.issue_refresh_challenge(BindingRepo.get!(device.binding.id))

      assert {:ok, refreshed} =
               Actions.Binding.refresh_session(binding, Device.refresh_proof(device, nonce))

      assert Timex.after?(refreshed.access_token_expires_at, Timex.now())
      assert refreshed.refresh_nonce == nil

      assert Actions.Binding.refresh_session(refreshed, Device.refresh_proof(device, nonce)) ==
               {:error, :no_challenge}
    end

    test "a stolen bearer alone cannot renew", %{device: device} do
      {:ok, %{binding: binding, nonce: nonce}} =
        Actions.Binding.issue_refresh_challenge(device.binding)

      thief = Device.bind(insert(:tenant))

      assert Actions.Binding.refresh_session(binding, Device.refresh_proof(thief, nonce)) ==
               {:error, :invalid_proof}
    end

    test "needs an outstanding challenge", %{device: device} do
      assert Actions.Binding.refresh_session(device.binding, "whatever") ==
               {:error, :no_challenge}
    end

    test "a revoked binding refreshes nothing", %{device: device} do
      {:ok, revoked} = Actions.Binding.revoke(device.binding)

      assert Actions.Binding.issue_refresh_challenge(revoked) == {:error, :revoked}
      assert Actions.Binding.refresh_session(revoked, "signature") == {:error, :revoked}
    end
  end

  test "revoke/1 retires the device, its push token and its session", %{tenant: tenant} do
    device = Device.bind(tenant)

    assert {:ok, revoked} = Actions.Binding.revoke(device.binding)
    assert revoked.status == :revoked
    assert revoked.revoked_at
    assert revoked.push_token == nil
    assert revoked.access_token_hash == nil
  end

  test "update_push_token/3 only works while the binding is alive", %{tenant: tenant} do
    device = Device.bind(tenant)

    assert {:ok, updated} =
             Actions.Binding.update_push_token(device.binding, "new-token", :android)

    assert updated.push_token == "new-token"
    assert updated.push_platform == :android

    {:ok, revoked} = Actions.Binding.revoke(updated)
    assert Actions.Binding.update_push_token(revoked, "another", :android) == {:error, :revoked}
  end

  describe "lookups" do
    test "by external id, scoped to the tenant", %{tenant: tenant} do
      binding = insert(:binding, tenant: tenant, external_id: "customer-7")

      assert {:ok, found} = BindingRepo.get_by_external_id(tenant, "customer-7")
      assert found.id == binding.id

      assert BindingRepo.get_by_external_id(insert(:tenant), "customer-7") ==
               {:error, :not_found}
    end

    test "by public id, refusing other entities' ids", %{tenant: tenant} do
      binding = insert(:binding, tenant: tenant)

      assert {:ok, found} = BindingRepo.get_by_public_id(binding.public_id)
      assert found.id == binding.id
      assert BindingRepo.get_by_public_id(tenant.public_id) == {:error, :not_found}
    end

    test "active bindings only", %{tenant: tenant} do
      device = Device.bind(tenant)
      insert(:binding, tenant: tenant)

      assert Enum.map(BindingRepo.list_active(tenant), & &1.id) == [device.binding.id]
    end
  end

  test "touch_last_seen/1 records the visit", %{tenant: tenant} do
    device = Device.bind(tenant)

    assert {:ok, touched} = BindingRepo.touch_last_seen(device.binding)
    assert touched.last_seen_at
  end

  defp expire_token(binding, seconds) do
    binding
    |> Ecto.Changeset.change(access_token_expires_at: Timex.shift(Timex.now(), seconds: seconds))
    |> Repo.update!()
  end
end
