# The blueprint under `docs/` is written by `test/sca_api/api_docs_test.exs`,
# and only when `DOC` asks for it — an ordinary `mix test` leaves the file
# alone. `mix api.docs` is what sets it.
Bureaucrat.start(
  writer: ScaApi.BlueprintWriter,
  default_path: Path.expand("../../../docs/api.apib", __DIR__),
  paths: [],
  titles: [],
  env_var: "DOC",
  json_library: Jason
)

ExUnit.start(formatters: [ExUnit.CLIFormatter, Bureaucrat.Formatter])
Ecto.Adapters.SQL.Sandbox.mode(Sca.Repo, :manual)
