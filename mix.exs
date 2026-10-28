defmodule Jido.Chat.Telegram.MixProject do
  use Mix.Project

  @version "3.0.0-dev"
  @jido_chat_ref "0b6f16d9b91b37c61f2ad913dcdd4adea1713f88"
  @source_url "https://github.com/agentjido/jido_chat_telegram"
  @description "Telegram adapter package for Jido.Chat"

  def project do
    [
      app: :jido_chat_telegram,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido Chat Telegram",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90],
        export: "cov"
      ],
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix, :jido, :ex_unit]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        quality: :test,
        q: :test,
        "test.contracts": :test,
        cover: :test,
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp chat_dependency do
    case {Mix.env(), System.get_env("JIDO_CHAT_PATH")} do
      {env, path} when env in [:dev, :test] and is_binary(path) and path != "" ->
        {:jido_chat, path: Path.expand(path, __DIR__), override: true}

      {env, _path} when env in [:dev, :test] ->
        {:jido_chat, github: "agentjido/jido_chat", ref: @jido_chat_ref, override: true}

      _ ->
        {:jido_chat, "~> 3.0.0-dev"}
    end
  end

  defp deps do
    [
      # Runtime dependencies
      {:ex_gram, "~> 0.69"},
      {:jason, "~> 1.4"},
      chat_dependency(),
      {:req, "~> 0.7.1"},

      # Development and test dependencies
      {:covenant, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:dotenvy, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      install_hooks: ["git_hooks.install"],
      q: ["quality"],
      "test.contracts": ["covenant.check"],
      cover: ["coveralls"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "guides", "mix.exs", "README.md", "LICENSE", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Discord" => "https://jido.run/discord",
        "Documentation" => "https://hexdocs.pm/jido_chat_telegram",
        "GitHub" => @source_url,
        "Website" => "https://jido.run"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "guides/contracts.md"
      ]
    ]
  end
end
