defmodule ScaUi.MixProject do
  use Mix.Project

  def project do
    [
      app: :sca_ui,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_html, "~> 4.1"},
      {:timex, "~> 3.7"}
    ]
  end
end
