defmodule Spearmint.MixProject do
  use Mix.Project

  @version "0.0.0"
  @source_url "private_host"

  def project do
    [
      app: :spearmint,
      version: @version,
      name: "spearmint",
      licenses: "Apache-2.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        # Mapset opaqueness issue presents in server.ex
        flags: [:no_opaque]
      ],
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: [
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.lcov": :test,
        "coveralls.xml": :test,
        coveralls: :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:elixir_uuid, "~> 1.2", warn_if_outdated: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false, warn_if_outdated: true},
      {:ex2ms, "~> 1.7", warn_if_outdated: true},
      {:excoveralls, "~> 0.18", only: :test, warn_if_outdated: true},
      {:lua, "~> 1.0", warn_if_outdated: true},
      {:memoize, "~> 1.4", warn_if_outdated: true}
    ]
  end

  defp package do
    [
      maintainers: ["ComradeComputer"],
      licenses: ["Apache-2.0"]
    ]
  end

  def description do
    """
    Spearmint is an Entity Component System (ECS) library for Elixir
    It is a fork of ECSpanse. The code has been modified to bring frame based simulation instead of time based simulation

    The goal is to eventually support:
     - Parallel execution of multiple ECS simulations in a single BEAM instance
    """
  end

  defp docs do
    [
      main: "Spearmint",
      source_ref: "v#{@version}",
      logo: nil,
      # extra_section: "GUIDES",
      source_url: @source_url,
      extras: [],
      groups_for_docs: [
        Generic: &(&1[:group] == :generic),
        Entities: &(&1[:group] == :entities),
        Export: &(&1[:group] == :export),
        Restore: &(&1[:group] == :restore),
        Relationships: &(&1[:group] == :relationships),
        Components: &(&1[:group] == :components),
        Resources: &(&1[:group] == :resources),
        Tags: &(&1[:group] == :tags),
        "Implemented Callbacks": &(&1[:group] == :implemented)
      ],
      nest_modules_by_prefix: [
        Spearmint.Entity,
        Spearmint.Component,
        Spearmint.System,
        Spearmint.Resource,
        Spearmint.Event,
        Spearmint.Query,
        Spearmint.Command,
        Spearmint.Template,
        Spearmint.Projection,
        Spearmint.Snapshot
      ],
      groups_for_modules: [
        API: [
          Spearmint,
          Spearmint.Data,
          Spearmint.Frame,
          Spearmint.Simulation
        ],
        Entities: [Spearmint.Entity],
        Components: [
          Spearmint.Component,
          Spearmint.Component.Children,
          Spearmint.Component.Parents
        ],
        Systems: [
          Spearmint.System,
          Spearmint.System.WithEventSubscriptions,
          Spearmint.System.WithoutEventSubscriptions,
          Spearmint.System.CreateStartupResources,
          Spearmint.System.Timer,
          Spearmint.System.TrackFPS,
          Spearmint.System.Debug
        ],
        Resources: [Spearmint.Resource, Spearmint.Resource.FPS],
        States: [Spearmint.State],
        Events: [Spearmint.Event],
        Queries: [Spearmint.Query],
        Commands: [Spearmint.Command],
        Templates: [
          Spearmint.Template.Component,
          Spearmint.Template.Component.Timer,
          Spearmint.Template.Event,
          Spearmint.Template.Event.Timer
        ],
        Projections: [Spearmint.Projection],
        Snapshots: [Spearmint.Snapshot]
      ]
    ]
  end
end
