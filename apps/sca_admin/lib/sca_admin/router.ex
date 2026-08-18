defmodule ScaAdmin.Router do
  use ScaAdmin, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ScaAdmin.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ScaAdmin do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", ScaAdmin do
  #   pipe_through :api
  # end

  # Oban queues and jobs. No authentication yet, so it stays behind dev_routes
  # together with the LiveDashboard — move both into an authenticated scope
  # once admin login exists.
  if Application.compile_env(:sca_admin, :dev_routes) do
    import Oban.Web.Router

    scope "/dev" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:sca_admin, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ScaAdmin.Telemetry
    end
  end
end
