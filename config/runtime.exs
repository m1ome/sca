import Config

# Runs for every environment, releases included: after compilation, before the
# system starts. Everything read from the environment lives here.

# The three endpoints differ only in variable names, hence a table.
endpoints = [
  {:sca_web, ScaWeb.Endpoint, "WEB", "4000"},
  {:sca_api, ScaApi.Endpoint, "API", "4001"},
  {:sca_admin, ScaAdmin.Endpoint, "ADMIN", "4002"}
]

for {app, endpoint, prefix, default_port} <- endpoints do
  config app, endpoint,
    http: [port: String.to_integer(System.get_env("#{prefix}_PORT", default_port))]
end

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  release: System.get_env("RELEASE_VSN")

# The Firebase service account, base64 in one variable: no file to mount, no
# newlines in a private key to fight. Without it push is simply off.
case System.get_env("FCM_CREDENTIALS") do
  nil ->
    :ok

  encoded ->
    credentials =
      case Base.decode64(encoded, ignore: :whitespace) do
        {:ok, json} ->
          Jason.decode!(json)

        :error ->
          raise """
          FCM_CREDENTIALS must be the service account JSON in base64.
          For example: base64 -i service-account.json | tr -d '\\n'
          """
      end

    config :sca, Sca.Push,
      project_id: System.get_env("FCM_PROJECT_ID") || credentials["project_id"],
      credentials: credentials
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  for {app, endpoint, prefix, _default_port} <- endpoints do
    config app, endpoint,
      # Absolute links and LiveView's origin check: what the world calls us,
      # which is the proxy terminating TLS, not this port. PHX_HOST covers all
      # three; WEB_HOST / API_HOST / ADMIN_HOST split them across domains.
      url: [
        host: System.get_env("#{prefix}_HOST") || System.get_env("PHX_HOST") || "localhost",
        port: 443,
        scheme: "https"
      ],
      # All interfaces, IPv6 included: {0, 0, 0, 0, 0, 0, 0, 1} is localhost only.
      http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
      secret_key_base: secret_key_base,
      # There is no `mix phx.server` in a release.
      server: true
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :sca, Sca.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []),
    # Verified against the system store, otherwise it is TLS for show.
    ssl:
      if(System.get_env("DATABASE_SSL") in ~w(true 1),
        do: [cacerts: :public_key.cacerts_get()],
        else: false
      )

  config :sca, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
