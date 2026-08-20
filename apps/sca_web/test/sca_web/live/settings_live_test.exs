defmodule ScaWeb.SettingsLiveTest do
  use ScaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sca.Repos.TenantRepo
  alias ScaWeb.Fixtures

  @certificate File.read!(
                 Path.expand("../../../../sca/test/support/fixtures/webhook_cert.pem", __DIR__)
               )

  setup %{conn: conn} do
    %{tenant: tenant, user: user} = Fixtures.merchant()

    %{conn: Fixtures.log_in(conn, user), tenant: tenant}
  end

  test "shows the webhook and hides the signing key until asked", ctx do
    {:ok, live, html} = live(ctx.conn, ~p"/settings")

    assert html =~ "Webhook"
    assert html =~ "Signing key"
    refute html =~ ctx.tenant.settings.webhook_secret

    html = live |> element("button", "Reveal") |> render_click()

    assert html =~ ctx.tenant.settings.webhook_secret
    assert html =~ "Hide"
  end

  test "saves the endpoint, the certificate and the timeout", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/settings")

    html =
      live
      |> form("#settings-form",
        settings: %{
          webhook_url: "https://merchant.example.com/hooks/sca",
          webhook_certificate: @certificate,
          default_request_timeout_seconds: "90"
        }
      )
      |> render_submit()

    assert html =~ "Settings saved"

    {:ok, tenant} = TenantRepo.get(ctx.tenant.id)
    assert tenant.settings.webhook_url == "https://merchant.example.com/hooks/sca"
    assert tenant.settings.webhook_certificate =~ "BEGIN CERTIFICATE"
    assert tenant.settings.default_request_timeout_seconds == 90
  end

  test "refuses a certificate it could not encrypt for", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/settings")

    html =
      live
      |> form("#settings-form",
        settings: %{webhook_certificate: "-----BEGIN CERTIFICATE-----\nnope"}
      )
      |> render_submit()

    assert html =~ "webhook_certificate"
    refute html =~ "Settings saved"
  end

  test "refuses an absurd timeout", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/settings")

    html =
      live
      |> form("#settings-form", settings: %{default_request_timeout_seconds: "5"})
      |> render_submit()

    refute html =~ "Settings saved"

    assert {:ok, %{settings: %{default_request_timeout_seconds: 300}}} =
             TenantRepo.get(ctx.tenant.id)
  end

  test "rotating the signing key asks first, then replaces it", ctx do
    {:ok, live, _html} = live(ctx.conn, ~p"/settings")

    html = live |> element("button", "Rotate key") |> render_click()
    assert html =~ "Rotate the signing key?"

    html = live |> element("#rotate-key button", "Rotate key") |> render_click()

    assert html =~ "rotated"
    {:ok, tenant} = TenantRepo.get(ctx.tenant.id)
    refute tenant.settings.webhook_secret == ctx.tenant.settings.webhook_secret
    assert html =~ tenant.settings.webhook_secret
  end

  test "lists what we sent to the endpoint", ctx do
    {:ok, tenant} =
      Sca.Actions.Tenant.update_settings(ctx.tenant, %{
        webhook_url: "https://merchant.example.com/hooks/sca"
      })

    {:ok, pending} = Sca.Actions.Binding.enroll(tenant, %{external_id: "customer-1"})

    {:ok, _session} =
      Sca.Actions.Binding.bind(pending.enroll_token, %{
        public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0))
      })

    {:ok, _live, html} = live(ctx.conn, ~p"/settings")

    assert html =~ "Recent deliveries"
    assert html =~ "binding.activated"
    assert html =~ "Not sent yet"
  end
end
