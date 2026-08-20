defmodule ScaAdmin.Router do
  use ScaAdmin, :router

  import ScaAdmin.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ScaAdmin.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ScaAdmin do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/log-in", SessionController, :new
    post "/log-in", SessionController, :create
  end

  scope "/", ScaAdmin do
    pipe_through [:browser, :require_authenticated_admin]

    delete "/log-out", SessionController, :delete

    live_session :console,
      on_mount: {ScaAdmin.Auth, :ensure_authenticated},
      layout: false do
      live "/", OverviewLive
      live "/tenants", TenantsLive
      live "/tenants/:id", TenantLive
      live "/bindings", BindingsLive
      live "/approvals", ApprovalsLive
      live "/team", TeamLive
      live "/team/:id", TeamMemberLive
      live "/settings", SettingsLive
    end
  end

  # Unauthenticated, hence dev only — as is the LiveDashboard below.
  if Application.compile_env(:sca_admin, :dev_routes) do
    import Oban.Web.Router

    scope "/dev" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:sca_admin, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ScaAdmin.Telemetry
    end
  end
end
