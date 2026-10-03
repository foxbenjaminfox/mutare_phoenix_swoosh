# mutare_phoenix_swoosh

[![Hex.pm](https://img.shields.io/hexpm/v/mutare_phoenix_swoosh.svg)](https://hex.pm/packages/mutare_phoenix_swoosh)
[![Hexdocs](https://img.shields.io/badge/hexdocs-docs-blue.svg)](https://hexdocs.pm/mutare_phoenix_swoosh)
[![CI](https://github.com/foxbenjaminfox/mutare_phoenix_swoosh/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/foxbenjaminfox/mutare_phoenix_swoosh/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/mutare_phoenix_swoosh.svg)](https://github.com/foxbenjaminfox/mutare_phoenix_swoosh/blob/master/LICENSE)

Mutation-testing mutators for the
[phoenix_swoosh](https://hexdocs.pm/phoenix_swoosh) template-rendering
surface — the layer `Phoenix.Swoosh` adds on top of a
[Swoosh](https://hexdocs.pm/swoosh) mailer — built as a plugin for
[Mutare](https://hexdocs.pm/mutare).

Template-rendered email has its own signature test gap: the suite asserts the
email was *sent*, and nothing more. A `render_body` that never ran, a `.text`
template that broke while the `.html` part kept passing (or the reverse), a
branded layout that no longer wraps the body — all pass such a test.
`mutare_phoenix_swoosh` generates *well-formed-but-wrong* mailer programs at
exactly those spots, so a **surviving** mutant points at the precise assertion
your suite is missing.

It **builds on** [`mutare_swoosh`](https://hexdocs.pm/mutare_swoosh) (the base
email-construction and delivery families) the way `phoenix_swoosh` builds on
`swoosh`: it depends on it, so those families are on your code path too, ready
to compose.

## Install

Add it (with Mutare and the base package) as dev/test dependencies:

```elixir
def deps do
  [
    {:mutare, "~> 0.5.0", only: [:dev, :test], runtime: false},
    {:mutare_swoosh, "~> 0.2", only: [:dev, :test], runtime: false},
    {:mutare_phoenix_swoosh, "~> 0.2", only: [:dev, :test], runtime: false}
  ]
end
```

(Neither `phoenix_swoosh` nor `swoosh` is a dependency of this plugin — the
mutators match calls purely syntactically. Your own project already supplies
them.)

## Enable

Splice the families into `.mutare.exs` alongside Mutare's built-ins and the
`mutare_swoosh` preset, and list `Mutare.Phoenix.Swoosh` under `:extensions`
(see ["Why the `:extensions` entry"](#why-the-extensions-entry) below):

```elixir
# .mutare.exs — a phoenix_swoosh mailer app
[
  mutators:
    [:builtins] ++
      Mutare.Swoosh.all(mailer: MyApp.Mailer) ++
      Mutare.Phoenix.Swoosh.all(),
  extensions: [Mutare.Phoenix.Swoosh]
]
```

`Mutare.Phoenix.Swoosh.all/0` returns only this package's two families — it
does **not** include the base `mutare_swoosh` families, so compose
`Mutare.Swoosh.all/1` explicitly as shown for the full Swoosh + template
surface. Then run Mutare as usual:

```
mix mutare
```

## The families

| Family | Name | Mutation | The gap a survivor exposes |
| --- | --- | --- | --- |
| `Mutare.Phoenix.Swoosh.RenderBody` | `:render_body` | removes a `render_body/2,3` call (`remove` — the email is sent with no rendered body); narrows a literal atom template to one of its string forms (`html_only` / `text_only` — only that body part renders); drops one entry from a literal `put_new_formats/2` map (`format` — that extension stops rendering) | no test asserts the rendered body, or tests assert only *one* of the body parts |
| `Mutare.Phoenix.Swoosh.Layout` | `:mail_layout` | removes `put_layout/2` (`put`) / `put_new_layout/2` (`put_new`), collapsing to the email; sets the `layout:` assign of a `render_body` call to `false` (`off` — the body renders with no layout at all) | no test asserts which layout wrapped the rendered body |

Each family matches its call written qualified
(`Phoenix.Swoosh.render_body(...)`), aliased, bare-imported (the form
`use Phoenix.Swoosh` produces — the wrapper's default-assigns `render_body/2`
included), or as a pipe stage, and every replacement is itself a valid
phoenix_swoosh program — a survivor means a missing assertion, not a crash.

Both families also *pin* phoenix_swoosh's structural argument positions
against Mutare's built-in value families: the template name, the layout tuple
(interior included), and the `put_new_formats/2` map. A perturbed template or
layout is a missing-template crash at render time — an uninformative kill,
never a test-quality signal — so core's literal families do not generate mutants
there. The `format` mutation drops a whole map entry while the `:raw` route
excludes the map's contents from mutation by any family. This tests whether
the missing body part is asserted without changing template identifiers.

### Why `:mail_layout` mutates the render call

Idiomatic mailers rarely call `put_layout` at all — the layout goes on the
`use` line (`use Phoenix.Swoosh, view: MyApp.EmailView, layout: {MyApp.LayoutView, :email}`),
which is compile-time configuration no mutant can be delivered into (see
["What's deliberately out of scope"](#whats-deliberately-out-of-scope)). The
`off` mutant overrides the same layout at runtime through `render_body`'s
assigns. phoenix_swoosh uses a per-render override when present and otherwise
uses the email's layout.

Suppressing a layout that was never in effect would be an equivalent mutant —
unkillable — so `off` is generated only where a layout demonstrably *is* in
effect:

- the mailer's `use` line configured one (the `:extensions` entry reports that
  to the family; see below), or
- the call's own assigns literal contains a truthy `layout:` entry.

A mailer that configures its layout by *calling* `put_layout` gets the `put`
removal at that call instead, testing the same gap without a second mutation
at the render call.

## Ignoring one kind of mutant

The families declare ignore-variant labels, so a
`# mutare:ignore[family:label]` directive can suppress one kind of mutant
without silencing the whole family:

```elixir
email |> render_body(:welcome, assigns)   # mutare:ignore[render_body:text_only] no text part shipped
email |> render_body(:welcome, assigns)   # mutare:ignore[mail_layout:off] layout asserted elsewhere
email |> put_layout({LayoutView, :email}) # mutare:ignore[mail_layout:put]
email |> put_new_formats(@formats)        # mutare:ignore[render_body:format]
```

## Why the `:extensions` entry

`use Phoenix.Swoosh` defines a local `render_body` wrapper rather than
importing it: its `__using__` injects
`import Phoenix.Swoosh, except: [render_body: 3]` plus a **local**
`def render_body(email, template, assigns \\ %{})` wrapper. The bare
`render_body` calls in a mailer module therefore resolve to a local
definition that Mutare's in-process `use` expansion does not resolve.

`Mutare.Phoenix.Swoosh` is therefore also a `Mutare.UseExpansion` extension:
listed under `:extensions`, it handles expansion of `use Phoenix.Swoosh` and
returns a **whole** `import Phoenix.Swoosh` standing in for the injected wrapper (which
forwards to `Phoenix.Swoosh.render_body/3` anyway). With it, bare
`render_body` calls — both wrapper arities — resolve, mutate, and get their
template position pinned.

The extension also records whether the `use` line configured a layout, using
the `Mutare.Phoenix.Swoosh.LayoutConfigured` marker. Mutare passes a `use`'s
injected behaviours to mutators as `context.behaviours`; that is the one
channel a `use` expansion has into a mutator, and it is how a compile-time
option gates a runtime mutant. The marker never reaches the metamutant, the
compiled program, or the report.

Without the `:extensions` entry the families still work on qualified and
aliased calls, and `:mail_layout` works on bare setter calls too (the layout
setters really are imported) — but bare `render_body` sites are neither
mutated nor pinned, and `off` is generated only where the author wrote the
`layout:` assign themselves.

## What's deliberately out of scope

- **Static config on the `use` line** — `use Phoenix.Swoosh, view: MyApp.EmailView,
  layout: {MyApp.LayoutView, :email}, formats: %{...}` is compile-time
  configuration: Mutare prunes `use` arguments (and module attributes) whole,
  because a runtime selector there is at best inert and at worst illegal — it
  could cause the single metamutant build to fail. Only runtime calls that use
  that configuration are mutable, which is why `:mail_layout` mutates the render
  call's `layout:` assign and `:render_body` mutates `put_new_formats/2`
  rather than the `use` options behind them.
- **The base Swoosh surface** — recipients, sender, subject, bodies, headers,
  attachments, and delivery are handled by the companion
  [`mutare_swoosh`](https://hexdocs.pm/mutare_swoosh), which this package
  depends on and composes with.
- **`put_view/2` / `put_new_view/2` removal** — a render with no view module
  raises at `render_body` time: a crash-kill, not a test-quality signal.
- **Assigns-entry dropping** — a template referencing the dropped assign
  raises at render; core's value families still mutate the assigns *values*
  as they would anywhere. This package mutates the `layout:` assign, which
  configures phoenix_swoosh rather than supplying template data.
- **Narrowing a layout name** (`{LayoutView, :email}` → `{LayoutView, "email.html"}`,
  so both parts render inside the *html* layout) — the exact analogue of the
  template narrowing, and a real gap ("no test asserts the text part's
  wrapper"), but whether an html layout renders cleanly around a text body is
  not yet verified against the real library. This mutation is deferred until
  that behaviour is verified.
- **Swapping `put_new_layout` for `put_layout`** (and the view setters) — the
  phoenix_swoosh analogue of core's `Mutare.Mutators.MapKeyword` `put ↔ put_new`
  lattice, and it would collide with nothing. Left out because the only
  `put_new_layout` call in a typical mailer is the one the `use` wrapper
  generates, and Mutare mutates author-written code, not macro-generated code.

## Tuning core's families at the assigns position

The assigns argument stays ordinary runtime data, so core's value families
mutate the values inside it — that is the point: a wrong interpolated value in
a body is caught only by a body-content assertion. One of core's mutants there
is a crash-kill rather than a signal, though: collapsing the whole assigns map
to `%{}` causes an error on the first `@assign` the template reads. Route that
one position `:interior` per-project if the noise bothers you — the map's own
node is never offered, while everything inside it still mutates:

```elixir
# .mutare.exs
[
  mutators: [:builtins] ++ Mutare.Swoosh.all(mailer: MyApp.Mailer) ++ Mutare.Phoenix.Swoosh.all(),
  extensions: [Mutare.Phoenix.Swoosh],
  call_routes: [{Phoenix.Swoosh, :render_body, 3, [:expression, :expression, :interior]}]
]
```

That covers the assigns map *itself*. It does not reach values nested inside
it — `:interior` excludes only the argument's own node, so core's alias and atom
families still perturb a `layout: {LayoutView, :email}` assign into
missing-template crash-kills. The package pins the layout only where it is a
whole argument (`put_layout/2`, `put_new_layout/2`). Use `# mutare:ignore` at
the site to suppress these mutations inside the assigns map, or leave them enabled.

## Development

The test suite runs against
stand-in `Phoenix.Swoosh`/`Swoosh.Email` modules
(`test/support/phoenix_swoosh_stubs.ex`) that mirror the real API — the
`__using__` with its `except:` import and local wrapper included — kept
faithful by hand, since a real `:phoenix_swoosh` test dep would collide with
them.

```
mix deps.get
mix test          # unit diffs + live semantic checks that a mutant actually changes behaviour
mix check         # format + credo + dialyzer
```

## License

MIT — see [LICENSE](LICENSE).
