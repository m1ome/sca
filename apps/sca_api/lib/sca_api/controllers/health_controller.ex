defmodule ScaApi.HealthController do
  @moduledoc """
  Unauthenticated liveness, which the mobile client uses as a ping.

  Deliberately answers before any binding exists — that is what makes it useful
  when the token is the thing in doubt.
  """

  use ScaApi, :controller

  # Monitoring hits this every few seconds; at info nothing else stays findable.
  plug Logster.ChangeConfig, status_2xx_level: :debug

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
