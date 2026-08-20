# Shared by every application in the umbrella.
import Config

config :sca_admin,
  ecto_repos: [Sca.Repo],
  generators: [context_app: :sca, binary_id: true]

# Configures the endpoint
config :sca_admin, ScaAdmin.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ScaAdmin.ErrorHTML, json: ScaAdmin.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sca.PubSub,
  live_view: [signing_salt: "YcWtDAZx"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sca_admin: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/sca_admin/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  sca_admin: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/sca_admin", __DIR__)
  ]

config :sca_api,
  ecto_repos: [Sca.Repo],
  generators: [context_app: :sca, binary_id: true]

# Configures the endpoint
config :sca_api, ScaApi.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ScaApi.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sca.PubSub,
  live_view: [signing_salt: "viAMYgJ5"]

config :sca,
  ecto_repos: [Sca.Repo],
  generators: [binary_id: true, timestamp_type: :utc_datetime_usec]

config :sca, Oban,
  repo: Sca.Repo,
  queues: [default: 10, webhooks: 20, push: 20],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Sca.Workers.RequestExpiryWorker}]}
  ]

# Inert without SENTRY_DSN: no network, no buffering.
config :sentry,
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

config :flop, repo: Sca.Repo, default_limit: 20

config :sca, :push_client, Sca.Push.Client.Fcm

# Swapping the HTTP client is a matter of pointing this elsewhere.
config :sca, :webhook_client, Sca.Webhooks.Client.Req

# Local adapter: the mailbox lives at "/dev/mailbox".
config :sca, Sca.Mailer, adapter: Swoosh.Adapters.Local

config :sca_web,
  ecto_repos: [Sca.Repo],
  generators: [context_app: :sca, binary_id: true]

# Configures the endpoint
config :sca_web, ScaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ScaWeb.ErrorHTML, json: ScaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sca.PubSub,
  live_view: [signing_salt: "X5Edvm6u"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sca_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/sca_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  sca_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/sca_web", __DIR__)
  ]

# One line per request (Logster) instead of Phoenix's four.
config :phoenix, :logger, false

config :logster,
  formatter: :logfmt,
  # Matched as substrings, so `token` covers access_, enroll_ and push_token.
  # `public_key` is not secret, just 90 useless characters of base64.
  filter_parameters: ~w(password secret token signature certificate public_key)

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Must stay at the bottom: it overrides everything above.
import_config "#{config_env()}.exs"
