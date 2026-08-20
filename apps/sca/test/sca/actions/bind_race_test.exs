defmodule Sca.Actions.BindRaceTest do
  @moduledoc """
  The one invariant that cannot be shown inside the sandbox: a QR code scanned
  by two devices at the same instant binds exactly one of them.

  Runs against the real database on its own connections — the sandbox hands
  every process the same connection, which is precisely the contention this test
  needs to create — so it is not async and cleans up after itself.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Sca.Actions
  alias Sca.Models
  alias Sca.Repo
  alias Sca.Repos.BindingRepo

  setup do
    Sandbox.mode(Repo, :auto)

    {:ok, %{tenant: tenant}} =
      Actions.Tenant.create(%{
        name: "Race Ltd",
        owner_email: "race-#{System.unique_integer([:positive])}@example.com"
      })

    on_exit(fn ->
      Sandbox.mode(Repo, :auto)
      Repo.delete_all(Oban.Job)
      Repo.delete(tenant)
      Sandbox.mode(Repo, :manual)
    end)

    %{tenant: tenant}
  end

  test "a QR scanned twice at the same moment binds exactly one device", %{tenant: tenant} do
    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-race"})

    results =
      [1, 2]
      |> Task.async_stream(
        fn _device ->
          {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)

          Actions.Binding.bind(pending.enroll_token, %{public_key: Base.encode64(public)})
        end,
        max_concurrency: 2,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _session}, &1)) == 1
    assert Enum.count(results, &match?({:error, _reason}, &1)) == 1

    {:ok, %Models.Binding{} = binding} = BindingRepo.get(pending.id)
    {:ok, %{binding: winner}} = Enum.find(results, &match?({:ok, _session}, &1))

    assert binding.status == :active
    assert binding.public_key == winner.public_key
    assert binding.enroll_token == nil
  end
end
