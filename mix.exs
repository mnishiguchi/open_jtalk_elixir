defmodule OpenJtalkElixir.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/mnishiguchi/open_jtalk_elixir"

  def project do
    [
      app: :open_jtalk_elixir,
      version: @version,
      description: "Use Open JTalk in Elixir",
      elixir: "~> 1.13",
      compilers: compilers(Mix.env()),
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      preferred_cli_env: %{
        credo: :lint,
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp compilers(:docs), do: Mix.compilers()
  defp compilers(:lint), do: Mix.compilers()
  defp compilers(_), do: [:elixir_make | Mix.compilers()]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:lint], runtime: false},
      {:elixir_make, "~> 0.7", runtime: false},
      {:ex_doc, "~> 0.38", only: [:docs], runtime: false}
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
        "lib",
        "scripts",
        "Makefile",
        "mix.exs",
        "CHANGELOG*",
        "README*",
        "LICENSE*"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Open JTalk" => "http://open-jtalk.sourceforge.net/",
        "HTS Engine API" => "http://hts-engine.sourceforge.net/",
        "MeCab" => "https://taku910.github.io/mecab/",
        "Open JTalk Dictionary " =>
          "https://sourceforge.net/projects/open-jtalk/files/Dictionary/",
        "MMDAgent Example (Mei voice)" =>
          "https://sourceforge.net/projects/mmdagent/files/MMDAgent_Example/"
      }
    }
  end
end
