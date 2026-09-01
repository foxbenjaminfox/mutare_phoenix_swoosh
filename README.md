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
| `Mutare.Phoenix.Swoosh.RenderBody` | `:render_body` | removes a `render_body/2,3` call (`remove` — the email ships with no rendered body); narrows a literal atom template to one of its string forms (`html_only` / `text_only` — only that body part renders) | no test asserts the rendered body — or asserts only *one* of the two body parts, the classic "the text part broke and nobody noticed" |
| `Mutare.Phoenix.Swoosh.Layout` | `:mail_layout` | removes `put_layout/2` (`put`) / `put_new_layout/2` (`put_new`), collapsing to the email | no test asserts which layout wrapped the rendered body |

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
there.

## Ignoring one kind of mutant

The families declare ignore-variant labels, so a
`# mutare:ignore[family:label]` directive can suppress one kind of mutant
without silencing the whole family:

```elixir
email |> render_body(:welcome, assigns)   # mutare:ignore[render_body:text_only] no text part shipped
email |> put_layout({LayoutView, :email}) # mutare:ignore[mail_layout:put]
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
template position pinned. Without it, the families still work on qualified and
aliased calls, and `:mail_layout` works on bare calls too (the layout setters
really are imported) — but bare `render_body` sites are neither mutated nor
pinned.

## What's deliberately out of scope

- **The base Swoosh surface** — recipients, sender, subject, bodies, headers,
  attachments, and delivery live in the companion
  [`mutare_swoosh`](https://hexdocs.pm/mutare_swoosh), which this package
  depends on and composes with.
- **`put_view/2` / `put_new_view/2` removal** — a render with no view module
  raises at `render_body` time: a crash-kill, not a test-quality signal.
- **Assigns-entry dropping** — a template referencing the dropped assign
  raises at render; core's value families still mutate the assigns *values*
  as they would anywhere.

## Development

The plugin is developed against sibling checkouts of Mutare and the base
package (`{:mutare, path: "../mutare"}`,
`{:mutare_swoosh, path: "../mutare_swoosh"}`). The test suite runs against
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
