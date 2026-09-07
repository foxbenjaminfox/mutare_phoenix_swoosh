# mutare_phoenix_swoosh

Mutation-testing mutators for the
[phoenix_swoosh](https://hexdocs.pm/phoenix_swoosh) template-rendering
surface — the layer `Phoenix.Swoosh` adds on top of a
[Swoosh](https://hexdocs.pm/swoosh) mailer — built as a plugin for
[Mutare](https://hexdocs.pm/mutare).

Template-rendered email has its own signature test gap: the suite asserts the
email was *sent*, and nothing more. A `render_body` that never ran, a `.text`
template that broke while the `.html` part kept passing (or the reverse), a
branded layout that quietly stopped wrapping the body — all pass such a test.
`mutare_phoenix_swoosh` mints *well-formed-but-wrong* mailer programs at
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
    {:mutare, "~> 0.1", only: [:dev, :test], runtime: false},
    {:mutare_swoosh, "~> 0.1", only: [:dev, :test], runtime: false},
    {:mutare_phoenix_swoosh, "~> 0.1", only: [:dev, :test], runtime: false}
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
| `Mutare.Phoenix.Swoosh.RenderBody` | `:render_body` | removes a `render_body/2,3` call (`remove` — the email ships with no rendered body); narrows a literal atom template to one of its string forms (`html_only` / `text_only` — only that body part renders); drops one entry from a literal `put_new_formats/2` map (`format` — that extension stops rendering) | no test asserts the rendered body — or asserts only *one* of the body parts, the classic "the text part broke and nobody noticed" |
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
never a test-quality signal — so core's literal families never mint mutants
there. Keeping a position raw for *everyone* and then minting the one safe
mutation there from its owner is what the `format` drop does: the map's keys
stay untouchable, and dropping a whole entry is the one rewrite that means
something.

### Why `:mail_layout` reaches into the render call

Idiomatic mailers rarely call `put_layout` at all — the layout goes on the
`use` line (`use Phoenix.Swoosh, view: MyApp.EmailView, layout: {MyApp.LayoutView, :email}`),
which is compile-time configuration no mutant can be delivered into (see
["What's deliberately out of scope"](#whats-deliberately-out-of-scope)). The
`off` mutant reaches the same layout through the seam it actually flows
through at runtime: `render_body`'s assigns, where phoenix_swoosh looks for a
per-render override before falling back to the email's layout.

Suppressing a layout that was never in effect would be an equivalent mutant —
unkillable, and this package does not mint those — so `off` fires only where a
layout demonstrably *is* in effect:

- the mailer's `use` line configured one (the `:extensions` entry reports that
  to the family; see below), or
- the call's own assigns literal carries a truthy `layout:` entry.

A mailer that configures its layout by *calling* `put_layout` gets the `put`
removal at that call instead — the same gap, owned once.

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

`use Phoenix.Swoosh` does not surface `render_body` the way most `use`s
surface their API: its `__using__` injects
`import Phoenix.Swoosh, except: [render_body: 3]` plus a **local**
`def render_body(email, template, assigns \\ %{})` wrapper. The bare
`render_body` calls a mailer module writes therefore resolve to a hidden local
definition — invisible to Mutare's (otherwise faithful) in-process `use`
expansion.

`Mutare.Phoenix.Swoosh` is therefore also a `Mutare.UseExpansion` extension:
listed under `:extensions`, it takes over `use Phoenix.Swoosh` and surfaces a
**whole** `import Phoenix.Swoosh` standing in for the injected wrapper (which
forwards to `Phoenix.Swoosh.render_body/3` anyway). With it, bare
`render_body` calls — both wrapper arities — resolve, mutate, and get their
template position pinned.

The extension also reads one *fact* out of the `use` line — whether the mailer
configured a layout — and reports it to `:mail_layout` as the
`Mutare.Phoenix.Swoosh.LayoutConfigured` marker. Mutare hands a `use`'s
injected behaviours to mutators as `context.behaviours`; that is the one
channel a `use` expansion has into a mutator, and it is how a compile-time
option gates a runtime mutant. The marker never reaches the metamutant, the
compiled program, or the report.

Without the `:extensions` entry the families still work on qualified and
aliased calls, and `:mail_layout` works on bare setter calls too (the layout
setters really are imported) — but bare `render_body` sites are neither
mutated nor pinned, and `off` fires only where the author wrote the `layout:`
assign themselves.

## What's deliberately out of scope

- **Static config on the `use` line** — `use Phoenix.Swoosh, view: MyApp.EmailView,
  layout: {MyApp.LayoutView, :email}, formats: %{...}` is compile-time
  configuration: Mutare prunes `use` arguments (and module attributes) whole,
  because a runtime selector there is at best inert and at worst illegal — it
  would sink the single build. Only the runtime calls that same configuration
  flows through are mutable, which is why `:mail_layout` mutates the render
  call's `layout:` assign and `:render_body` mutates `put_new_formats/2`
  rather than the `use` options behind them.
- **The base Swoosh surface** — recipients, sender, subject, bodies, headers,
  attachments, and delivery live in the companion
  [`mutare_swoosh`](https://hexdocs.pm/mutare_swoosh), which this package
  depends on and composes with.
- **`put_view/2` / `put_new_view/2` removal** — a render with no view module
  raises at `render_body` time: a crash-kill, not a test-quality signal.
- **Assigns-entry dropping** — a template referencing the dropped assign
  raises at render; core's value families still mutate the assigns *values*
  as they would anywhere. The one assigns entry this package does speak for is
  `layout:`, which is phoenix_swoosh vocabulary rather than template data.
- **Narrowing a layout name** (`{LayoutView, :email}` → `{LayoutView, "email.html"}`,
  so both parts render inside the *html* layout) — the exact analogue of the
  template narrowing, and a real gap ("no test asserts the text part's
  wrapper"), but whether an html layout renders cleanly around a text body is
  a fact about the real library this package has not verified. A mutant whose
  kill mode is unknown is not worth minting; deferred, not rejected.
- **Swapping `put_new_layout` for `put_layout`** (and the view setters) — the
  phoenix_swoosh analogue of core's `Mutare.Mutators.MapKeyword` `put ↔ put_new`
  lattice, and it would collide with nothing. Left out because the only
  `put_new_layout` call in a typical mailer is the one the `use` wrapper
  generates, and Mutare mutates what the author wrote, never what a macro
  wrote for them.

## Tuning core's families at the assigns position

The assigns argument stays ordinary runtime data, so core's value families
mutate the values inside it — that is the point: a wrong interpolated value in
a body is caught only by a body-content assertion. One of core's mutants there
is a crash-kill rather than a signal, though: collapsing the whole assigns map
to `%{}` kills itself on the first `@assign` the template reads. Route that
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
it — `:interior` spares only the argument's own node, so core's alias and atom
families still perturb a `layout: {LayoutView, :email}` assign into
missing-template crash-kills. The package pins the layout only where it is a
whole argument (`put_layout/2`, `put_new_layout/2`); inside the assigns map the
honest tools are `# mutare:ignore` at the site, or leaving it be.

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
