defmodule OpenJtalkElixir.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mnishiguchi/open_jtalk_elixir"

  def project do
    [
      app: :open_jtalk_elixir,
      version: @version,
      description: "Use Open JTalk in Elixir",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      aliases: [],
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package do
    %{
      files: [
        "CHANGELOG*",
        "config/*.exs",
        "lib",
        "LICENSE*",
        "mix.exs",
        "README.md"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    }
  end
end
