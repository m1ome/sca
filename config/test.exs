import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sca_admin, ScaAdmin.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4202],
  secret_key_base: "X8sYtp/1Oe5oz5JO6IpE2YCnL8G0nUHWABJHkXc+m6g5NbSUbt/VqXULGxlgxz5j",
  server: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sca_api, ScaApi.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4201],
  secret_key_base: "7cFKCj3aa22iCK8WdI97jGmUmtQvc1UNDtRgGnvMZrTnIcGYzfLp+tsnVJNH9/fy",
  server: false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sca, Sca.Repo,
  username: "sca",
  password: "sca",
  hostname: "localhost",
  port: 55433,
  database: "sca_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sca_web, ScaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4200],
  secret_key_base: "lgvgIuUW99XB/Lmbe5tMlCTklbktSGtR+3mMcJhIYmZblOMkMCtDWnt5DO1bTz5X",
  server: false

# Jobs are not executed in tests; assert on them with Oban.Testing instead.
config :sca, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails
config :sca, Sca.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
