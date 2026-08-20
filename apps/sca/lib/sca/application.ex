defmodule Sca.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # A no-op until SENTRY_DSN is set.
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line], capture_log_messages: true, level: :error}
    })

    children = [
      Sca.Repo,
      {DNSCluster, query: Application.get_env(:sca, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sca.PubSub},
      {Oban, Application.fetch_env!(:sca, Oban)}
    ]

    children =
      children ++ push_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Sca.Supervisor)
  end

  defp push_children do
    if Sca.Push.configured?() do
      # A revoked or malformed key kills Goth on its first token refresh, and
      # restarting it would take the whole application down with it. Push is
      # optional, the node is not: `:temporary` means push just stops.
      [
        Supervisor.child_spec(
          {Goth, name: Sca.Goth, source: {:service_account, Sca.Push.credentials()}},
          restart: :temporary
        )
      ]
    else
      []
    end
  end
end
