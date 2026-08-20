import Config

config :sca_admin, ScaAdmin.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "x+iuJeC19BQbi4AvI3kmnv8NhC1jov15Wuq51AudEaiVu5IbSdjAjKV1sRNdLHKj",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:sca_admin, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:sca_admin, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :sca_admin, ScaAdmin.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/sca_admin/router\.ex$"E,
      ~r"lib/sca_admin/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :sca_admin, dev_routes: true

config :sca_api, ScaApi.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "JcuOi4JKj77vYIZTUu990Wo/cAezKMP+Jac9lAiloK/Tt9ghgqMYG/NzvjQkw7Rc",
  watchers: []

config :sca_api, dev_routes: true

# Configure your database
config :sca, Sca.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  database: "sca_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :sca_web, ScaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "W+bpz11L/fr7RQO03VYgvw0bOfK2xbISJWcsstsHQbmevezx2tp5LOfJVoIAzRQQ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:sca_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:sca_web, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :sca_web, ScaWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      # Gettext translations
      ~r"priv/gettext/.*\.po$"E,
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/sca_web/router\.ex$"E,
      ~r"lib/sca_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :sca_web, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false

# Big stacktraces are a development luxury.
config :phoenix, :stacktrace_depth, 20
