defmodule ScaWeb.Router do
  use ScaWeb, :router

  import ScaWeb.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ScaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ScaWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/log-in", SessionController, :new
    post "/log-in", SessionController, :create
  end

  scope "/", ScaWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/log-out", SessionController, :delete

    live_session :console,
      on_mount: {ScaWeb.Auth, :ensure_authenticated},
      layout: false do
      live "/", OverviewLive
      live "/approvals", ApprovalsLive
      live "/approvals/:id", ApprovalLive
      live "/bindings", BindingsLive
      live "/bindings/:id", BindingLive
      live "/webhooks", WebhooksLive
      live "/team", TeamLive
      live "/team/:id", TeamMemberLive
      live "/settings", SettingsLive
    end
  end

  if Application.compile_env(:sca_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ScaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
