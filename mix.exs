defmodule Mutare.Phoenix.Swoosh.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/foxbenjaminfox/mutare_phoenix_swoosh"

  def project do
    [
      app: :mutare_phoenix_swoosh,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Mutare mutators for Phoenix.Swoosh"
  end

  # Hex package metadata. Only runtime and doc artifacts ship — never the test
  # suite or fixtures.
  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Benjamin Fox"],
      links: %{
        "GitHub" => @source_url,
        "Mutare" => "https://hexdocs.pm/mutare",
        "Changelog" => "https://hexdocs.pm/mutare_phoenix_swoosh/changelog.html"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp deps do
    [
      # The companion base package — this one **builds on** it: it depends on it and
      # composes its preset (`Mutare.Swoosh.all/1`) with the template-rendering families
      # on top (mirroring how `phoenix_swoosh` depends on `swoosh`). `mutare` itself
      # is also declared directly, since this package calls core's API itself; a
      # consuming project lists both as `:dev`/`:test` deps.
      #
      # `phoenix_swoosh` itself is deliberately NOT a dependency, not even in :test:
      # the mutators match calls syntactically, and the test suite's stand-ins
      # (test/support/phoenix_swoosh_stubs.ex) claim the real `Phoenix.Swoosh` /
      # `Swoosh.Email` module names so bare-import resolution reflects on real exports —
      # a real :phoenix_swoosh test dep would collide with them. Stub fidelity is
      # maintained against phoenix_swoosh's source by hand (see the stubs' comments).
      {:mutare, "~> 0.1"},
      {:mutare_swoosh, "~> 0.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # `mix check` is the single quality gate: formatting, lint, and type analysis.
  # Any non-zero step aborts the rest, so a green run means all three passed.
  defp aliases do
    [check: ["format --check-formatted", "credo", "dialyzer"]]
  end

  # Mutators are pure AST transforms over Sourceror nodes, so the most useful
  # specs to verify are the `Mutare.Mutator` callbacks. The PLT lives in a
  # cacheable, gitignored directory; `:mix` and `:ex_unit` are pulled in because
  # `mix.exs` and `test/support` participate in the analysis.
  #
  # `:extra_return` is deliberately *off*: every AST-constructor helper returns one
  # concrete `Macro.t()` shape, so its natural `:: Macro.t()` spec is broader than the
  # single node it builds — exactly what `:extra_return` would flag. The remaining flags
  # add real strictness without fighting that grain.
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :unmatched_returns]
    ]
  end

  # ExDoc configuration. `mix docs` renders to `doc/` (gitignored). README is the
  # landing page.
  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Mutator front": [Mutare.Phoenix.Swoosh],
        "Mutator families": [
          Mutare.Phoenix.Swoosh.RenderBody,
          Mutare.Phoenix.Swoosh.Layout
        ],
        # Not a behaviour anyone implements — the channel the `use` expansion uses to tell
        # `:mail_layout` that a layout is configured. Documented because a reader of a
        # `mail_layout:off` mutant will want to know why it fired here and not there.
        Marker: [Mutare.Phoenix.Swoosh.LayoutConfigured]
      ]
    ]
  end
end
