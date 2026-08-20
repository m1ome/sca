defmodule Sca.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      dialyzer: dialyzer(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # One release with every app. Split it per app when they scale separately.
  defp releases do
    [
      sca: [
        include_executables_for: [:unix],
        applications: [
          runtime_tools: :permanent,
          sca: :permanent,
          sca_api: :permanent,
          sca_web: :permanent,
          sca_admin: :permanent
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup"],
      lint: ["format --check-formatted", "credo --strict"],
      "ecto.reset": ["do --app sca ecto.reset"],
      # Only the two consoles have assets.
      "assets.deploy": [
        "do --app sca_web assets.deploy",
        "do --app sca_admin assets.deploy"
      ],
      # Dialyzer is minutes, not seconds — kept out of `precommit` on purpose.
      typecheck: ["dialyzer"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
