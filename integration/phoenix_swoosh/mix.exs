defmodule Mutare.Phoenix.Swoosh.Integration.MixProject do
  use Mix.Project

  def project do
    [
      app: :mutare_phoenix_swoosh_integration,
      version: "0.0.0",
      elixir: "~> 1.18",
      deps: [
        {:mutare_phoenix_swoosh, path: "../.."},
        {:phoenix_swoosh, "~> 1.2.1"},
        {:phoenix_html, "~> 4.0"}
      ]
    ]
  end
end
