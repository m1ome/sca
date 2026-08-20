defmodule Sca.Workers.RequestExpiryWorkerTest do
  use Sca.DataCase, async: true

  alias Sca.Actions
  alias Sca.Repos.RequestRepo
  alias Sca.Workers.RequestExpiryWorker

  setup do
    tenant = insert(:tenant)

    %{tenant: tenant, device: Device.bind(tenant)}
  end

  defp request(binding, expires_at) do
    {:ok, request} =
      Actions.Request.create(binding, %{
        type: :freeform,
        title: "Confirm",
        payload: %{"note" => "hello"},
        expires_at: expires_at
      })

    request
  end

  test "closes what is overdue and leaves the rest alone", ctx do
    overdue = request(ctx.device.binding, Timex.shift(Timex.now(), seconds: -1))
    live = request(ctx.device.binding, Timex.shift(Timex.now(), minutes: 5))

    assert {:ok, 1} = perform_job(RequestExpiryWorker, %{})

    assert RequestRepo.get!(overdue.id).status == :expired
    assert RequestRepo.get!(live.id).status == :pending
  end

  test "the merchant hears about every request it closed", ctx do
    overdue = request(ctx.device.binding, Timex.shift(Timex.now(), seconds: -1))

    {:ok, _count} = perform_job(RequestExpiryWorker, %{})

    assert [delivery] =
             overdue
             |> Sca.Repos.WebhookDeliveryRepo.list_for()
             |> Enum.filter(&(&1.event == "request.expired"))

    assert delivery.payload["request"]["status"] == "expired"
  end

  test "a run with nothing to do is not an error" do
    assert {:ok, 0} = perform_job(RequestExpiryWorker, %{})
  end
end
