defmodule Sca.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Sca.Repo,
      {DNSCluster, query: Application.get_env(:sca, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sca.PubSub},
      {Oban, Application.fetch_env!(:sca, Oban)}
      # Start a worker by calling: Sca.Worker.start_link(arg)
      # {Sca.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Sca.Supervisor)
  end
end
