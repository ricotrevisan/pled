defmodule Pled.MixProject do
  use Mix.Project

  def project do
    [
      app: :pled,
      version: "0.0.26-beta",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      aliases: aliases(),
      source_url: "https://github.com/ricotrevisan/pled",
      homepage_url: "https://github.com/ricotrevisan/pled",
      description: "A tool for Bubble.io plugin development"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Pled.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.4"},
      {:burrito, "~> 1.0"},
      {:slugify, "~> 1.3"},
      {:file_system, "~> 1.0"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp releases do
    targets =
      case Mix.env() do
        :dev ->
          [macos_arm: [os: :darwin, cpu: :aarch64]]

        _ ->
          [
            macos_x86: [os: :darwin, cpu: :x86_64],
            macos_arm: [os: :darwin, cpu: :aarch64],
            linux_arm: [os: :linux, cpu: :aarch64],
            linux_x86: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64]
          ]
      end

    [
      pled: [
        steps: [:assemble, &Burrito.wrap/1],
        applications: [runtime_tools: :none],
        burrito: [targets: targets]
      ]
    ]
  end

  defp aliases do
    [
      test: ["test --exclude integration"]
    ]
  end
end
