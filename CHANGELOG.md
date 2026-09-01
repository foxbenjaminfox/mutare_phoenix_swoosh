# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - Unreleased

Initial release.

### Added

- Two mutator families over the phoenix_swoosh template-rendering surface,
  each reported under its own name and independently enable-able:
  - `Mutare.Phoenix.Swoosh.RenderBody` (`:render_body`) — removes a
    `render_body/2,3` call, collapsing to the email (`remove` — the email
    ships with no rendered body), and narrows a literal atom template to each
    of its string forms (`html_only` / `text_only` — only the `.html` / only
    the `.text` body renders, the "one body part broke and nobody noticed"
    gap). Both wrapper arities fire, the `use`-injected default-assigns `/2`
    form included; a string or computed template gets the removal mutant
    alone.
  - `Mutare.Phoenix.Swoosh.Layout` (`:mail_layout`) — removes a layout
    setter, collapsing to the email: `put_layout/2` (`put` — the previous
    layout stays) and `put_new_layout/2` (`put_new` — the layout stays unset
    and the body renders bare).
- Structural pins on phoenix_swoosh's identifier positions, via macro-routing
  registry `:skip` routes covering the whole argument subtree: the template
  name, the layout value (tuple interior included), and `put_new_formats/2`'s
  extension→field map — a perturbed value there is a missing-template crash
  at render, so core's value families never mint mutants in those positions.
- A `Mutare.UseExpansion` extension (`Mutare.Phoenix.Swoosh` under
  `:extensions`) that takes over `use Phoenix.Swoosh` and surfaces a whole
  `import Phoenix.Swoosh` in place of the real injected
  `except: [render_body: 3]` import + local wrapper pair — the piece that
  makes bare `render_body` calls resolvable (and their witness safe) at all.
  The standalone `template_root:` style additionally surfaces the
  `import Phoenix.View` its nested `use` would inject.
- Every family matches its call written qualified, aliased, bare-imported, or
  piped (a piped removal becomes the `Function.identity()` no-op stage).
- Ignore-variant labels throughout, so `# mutare:ignore[family:label]` can
  suppress one kind of mutant (e.g. `[render_body:text_only]`,
  `[mail_layout:put]`).
- `Mutare.Phoenix.Swoosh.all/0` for splicing both families into a `:mutators`
  list, composing with the base `Mutare.Swoosh.all/1` preset from
  `mutare_swoosh` (a dependency of this package).
