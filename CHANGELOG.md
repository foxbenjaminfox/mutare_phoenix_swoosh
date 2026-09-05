# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - Unreleased

Initial release.

### Added

- Two mutator families over the phoenix_swoosh template-rendering surface,
  each reported under its own name and independently enable-able:
  - `Mutare.Phoenix.Swoosh.RenderBody` (`:render_body`) — the "which body
    parts render" seam. Removes a `render_body/2,3` call, collapsing to the
    email (`remove` — the email ships with no rendered body); narrows a
    literal atom template to each of its string forms (`html_only` /
    `text_only` — only the `.html` / only the `.text` body renders, the "one
    body part broke and nobody noticed" gap); and drops one entry per mutant
    from a literal `put_new_formats/2` map (`format` — that extension stops
    rendering, the custom-formats form of the same gap). Both wrapper arities
    fire, the `use`-injected default-assigns `/2` form included; a string or
    computed template gets the removal mutant alone, and a single-entry format
    map produces no drop (that is the `remove` mutant's diff).
  - `Mutare.Phoenix.Swoosh.Layout` (`:mail_layout`) — the "which layout wraps
    the body" seam. Removes a layout setter, collapsing to the email:
    `put_layout/2` (`put` — the previous layout stays) and `put_new_layout/2`
    (`put_new` — the layout stays unset and the body renders bare); and
    suppresses the layout at the render site by writing `layout: false` into
    `render_body`'s assigns (`off`), which is where a `use`-configured layout
    can be reached at runtime at all. `off` fires only where a layout is
    demonstrably in effect — the mailer's `use` line configured one, or the
    call's own assigns carry a truthy `layout:` — so it never mints an
    equivalent mutant. Literal map and keyword assigns gain the entry
    in place, an existing `layout:` entry is turned off rather than
    duplicated, a computed assigns argument is normalised the way
    phoenix_swoosh normalises it (`Enum.into/2` then `Map.put/3`), and the
    default-assigns `/2` form gains its assigns map without requalifying the
    bare call (which would skip the `use` wrapper's `put_new_view`).
- Structural pins on phoenix_swoosh's identifier positions, via call-routing
  registry `:raw` routes covering the whole argument subtree: the template
  name, the layout value (tuple interior included), and `put_new_formats/2`'s
  extension→field map — a perturbed value there is a missing-template crash
  at render, so core's value families never mint mutants in those positions.
  The format map's owner then mints the one safe mutation there itself.
- A `Mutare.UseExpansion` extension (`Mutare.Phoenix.Swoosh` under
  `:extensions`) that takes over `use Phoenix.Swoosh` and surfaces a whole
  `import Phoenix.Swoosh` in place of the real injected
  `except: [render_body: 3]` import + local wrapper pair — the piece that
  makes bare `render_body` calls resolvable (and their witness safe) at all.
  The standalone `template_root:` style additionally surfaces the
  `import Phoenix.View` its nested `use` would inject. The same expansion
  reports whether the `use` line configured a layout, as the
  `Mutare.Phoenix.Swoosh.LayoutConfigured` marker — the one channel a `use`
  expansion has into a mutator's context, and how a compile-time option gates
  a runtime mutant.
- Every family matches its call written qualified, aliased, bare-imported, or
  piped (a piped removal becomes the `Function.identity()` no-op stage).
- Ignore-variant labels throughout, so `# mutare:ignore[family:label]` can
  suppress one kind of mutant (e.g. `[render_body:text_only]`,
  `[render_body:format]`, `[mail_layout:put]`, `[mail_layout:off]`).
- `Mutare.Phoenix.Swoosh.all/0` for splicing both families into a `:mutators`
  list, composing with the base `Mutare.Swoosh.all/1` preset from
  `mutare_swoosh` (a dependency of this package).
- Documented scope: the `use Phoenix.Swoosh` line's own options are
  compile-time configuration Mutare prunes whole, so only the runtime calls
  that configuration flows through are mutable; layout-name narrowing and the
  `put_new_layout` ↔ `put_layout` swap are written down as deferrals with
  their reasons; and the README carries a verified recipe for pinning core's
  whole-assigns-map collapse per project.
