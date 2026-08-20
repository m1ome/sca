defmodule ScaWeb.WebhooksLiveTest do
  @moduledoc "The page someone opens when a decision did not reach their system."

  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  use Oban.Testing, repo: Sca.Repo

  alias Sca.Actions
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Webhooks
  alias ScaWeb.Fixtures

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()

    {:ok, tenant} =
      Actions.Tenant.update_settings(tenant, %{webhook_url: "https://merchant.example.com/hooks"})

    %{conn: Fixtures.log_in(conn, user), tenant: tenant}
  end

  defp deliver(tenant, event, attrs) do
    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-#{event}"})
    {:ok, delivery} = Webhooks.emit(event, pending)
    {:ok, delivery} = WebhookDeliveryRepo.record_attempt(delivery, attrs)

    delivery
  end

  test "lists what went out, with the answer and how many tries it took", ctx do
    delivery =
      deliver(ctx.tenant, "binding.activated", %{
        status: :delivered,
        attempts: 2,
        response_status: 200,
        delivered_at: Timex.now(),
        last_attempt_at: Timex.now()
      })

    {:ok, _live, html} = live(ctx.conn, ~p"/webhooks")

    assert html =~ "binding.activated"
    assert html =~ delivery.public_id
    assert html =~ "HTTP 200"
    assert html =~ "delivered"
  end

  test "filters by state and by event", ctx do
    delivered =
      deliver(ctx.tenant, "binding.activated", %{status: :delivered, response_status: 200})

    failed = deliver(ctx.tenant, "binding.revoked", %{status: :failed, error: "timeout"})

    {:ok, live, _html} = live(ctx.conn, ~p"/webhooks")

    # By id, not by event name: every event name is also a word in the filter.
    html = live |> form("form[phx-change=filter]", %{"status" => "failed"}) |> render_change()

    assert html =~ failed.public_id
    refute html =~ delivered.public_id

    html =
      live
      |> form("form[phx-change=filter]", %{"status" => "", "event" => "binding.activated"})
      |> render_change()

    assert html =~ delivered.public_id
    refute html =~ failed.public_id
  end

  test "opening one shows the endpoint, the error and the payload we sent", ctx do
    delivery =
      deliver(ctx.tenant, "binding.revoked", %{
        status: :failed,
        attempts: 8,
        error: "connection refused",
        last_attempt_at: Timex.now()
      })

    {:ok, live, _html} = live(ctx.conn, ~p"/webhooks")

    html = live |> element("button", "Open") |> render_click()

    assert html =~ "https://merchant.example.com/hooks"
    assert html =~ "connection refused"
    assert html =~ delivery.event
    assert html =~ "&quot;event&quot;"
  end

  test "a delivery whose job is still waiting is not queued twice", ctx do
    deliver(ctx.tenant, "binding.revoked", %{status: :failed, error: "timeout"})

    {:ok, live, _html} = live(ctx.conn, ~p"/webhooks")

    live |> element("button", "Open") |> render_click()
    html = live |> element("button", "Send again") |> render_click()

    assert html =~ "already waiting"
    assert Enum.count(all_enqueued(worker: Sca.Workers.WebhookDeliveryWorker)) == 1
  end

  test "a delivery whose job is done goes out again", ctx do
    delivery = deliver(ctx.tenant, "binding.revoked", %{status: :failed, error: "timeout"})
    Oban.Job |> Sca.Repo.all() |> Enum.each(&Sca.Repo.delete!/1)

    {:ok, live, _html} = live(ctx.conn, ~p"/webhooks")

    live |> element("button", "Open") |> render_click()
    html = live |> element("button", "Send again") |> render_click()

    assert html =~ "on its way again"
    assert_enqueued(worker: Sca.Workers.WebhookDeliveryWorker, args: %{delivery_id: delivery.id})
  end

  test "another merchant's deliveries are not listed", ctx do
    deliver(ctx.tenant, "binding.activated", %{status: :delivered, response_status: 200})

    %{tenant: other, user: stranger} = Fixtures.merchant()

    {:ok, other} =
      Actions.Tenant.update_settings(other, %{webhook_url: "https://other.example.com/hooks"})

    theirs = deliver(other, "binding.activated", %{status: :delivered, response_status: 200})

    {:ok, _live, html} = live(Fixtures.log_in(ctx.conn, stranger), ~p"/webhooks")

    assert html =~ theirs.public_id
    refute html =~ "1 in total\n"
  end
end
