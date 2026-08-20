defmodule ScaAdmin.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # One handler per node, one event for all three endpoints: whoever starts
    # second gets `:already_exists`, which is fine.
    _ = Logster.attach_phoenix_logger()

    children = [
      ScaAdmin.Telemetry,
      ScaAdmin.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ScaAdmin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ScaAdmin.Endpoint.config_change(changed, removed)
    :ok
  end
end
