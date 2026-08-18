defmodule Sca.Repo do
  use Ecto.Repo,
    otp_app: :sca,
    adapter: Ecto.Adapters.Postgres
end
