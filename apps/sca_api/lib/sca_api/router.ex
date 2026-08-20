defmodule ScaApi.Router do
  use ScaApi, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # A device that has just scanned a QR has no session yet.
  pipeline :device do
    plug ScaApi.DeviceAuth
  end

  # Renewing is the one thing an expired token must still be able to do.
  pipeline :device_renewal do
    plug ScaApi.DeviceAuth, renewal: true
  end

  # Devices reach us under `/t/:tenant`; the prefix is optional and resolved here.
  pipeline :tenant_path do
    plug ScaApi.TenantPath
  end

  pipeline :merchant do
    plug ScaApi.MerchantAuth
  end

  scope "/api", ScaApi do
    pipe_through :api
  end

  scope "/", ScaApi do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  # The device API. Its shape is fixed by the mobile client: it takes the base
  # URL from the QR and appends `/api/sca/v1/...` to it, so mounting the same
  # routes under `/t/:tenant` is what puts the merchant in every device call.
  scope "/t/:tenant", ScaApi do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  for prefix <- ["/api/sca/v1", "/t/:tenant/api/sca/v1"] do
    scope prefix, ScaApi do
      pipe_through [:api, :tenant_path]

      post "/connections", DeviceController, :bind
    end

    scope prefix, ScaApi do
      pipe_through [:api, :tenant_path, :device_renewal]

      post "/connections/self/refresh/challenge", DeviceController, :refresh_challenge
      post "/connections/self/refresh", DeviceController, :refresh
    end

    scope prefix, ScaApi do
      pipe_through [:api, :tenant_path, :device]

      get "/authorizations", DeviceController, :pending
      get "/authorizations/:id", DeviceController, :show
      put "/authorizations/:id", DeviceController, :decide
      put "/connections/self/push-token", DeviceController, :push_token
      post "/connections/:id/revoke", DeviceController, :revoke
    end
  end

  scope "/api/merchant/v1", ScaApi do
    pipe_through [:api, :merchant]

    post "/bindings", MerchantController, :create_binding
    get "/bindings", MerchantController, :list_bindings
    get "/bindings/:id", MerchantController, :show_binding
    post "/bindings/:id/revoke", MerchantController, :revoke_binding

    post "/approvals", MerchantController, :create_approval
    get "/approvals", MerchantController, :list_approvals
    get "/approvals/:id", MerchantController, :show_approval
    post "/approvals/:id/cancel", MerchantController, :cancel_approval
  end

  if Application.compile_env(:sca_api, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ScaApi.Telemetry
    end
  end
end
