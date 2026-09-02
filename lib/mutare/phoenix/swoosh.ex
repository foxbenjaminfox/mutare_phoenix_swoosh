defmodule Mutare.Phoenix.Swoosh do
  @moduledoc """
  [Mutare](https://hex.pm/packages/mutare) mutators for the
  [phoenix_swoosh](https://hexdocs.pm/phoenix_swoosh) template-rendering surface — the layer
  `Phoenix.Swoosh` adds on top of a Swoosh mailer.

  This package depends on `mutare_swoosh`, so the base email-construction/delivery families are
  on your code path too; compose the two presets for a full mailer surface (see "Usage").

  ## Families

    * `Mutare.Phoenix.Swoosh.RenderBody` — `:render_body`: remove a `render_body/2,3` call
      (the email ships with no rendered body), narrow an atom template to one of its two string
      forms (only the `.html` / only the `.text` body renders), or drop one entry from a
      literal `put_new_formats/2` map (that extension stops rendering).
    * `Mutare.Phoenix.Swoosh.Layout` — `:mail_layout`: remove a `put_layout/2` /
      `put_new_layout/2` call (the body renders in the previous/no layout), or suppress the
      layout at the render site by setting the `layout:` assign to `false` (the body renders
      bare wherever the layout was configured).

  Both families also pin phoenix_swoosh's structural argument positions — the template name,
  the layout tuple, the `put_new_formats/2` map — so core's value families never mint the
  missing-template crash mutants those positions would otherwise get.

  ## Usage

  Splice `all/0` into `:mutators` alongside the `:builtins` group token and the `mutare_swoosh`
  preset, and list this module under `:extensions` (see below for why):

      # .mutare.exs — a phoenix_swoosh mailer app
      [
        mutators:
          [:builtins] ++
            Mutare.Swoosh.all(mailer: MyApp.Mailer) ++
            Mutare.Phoenix.Swoosh.all(),
        extensions: [Mutare.Phoenix.Swoosh]
      ]

  `all/0` returns only this package's two families — it does not include the base
  `mutare_swoosh` families, so compose `Mutare.Swoosh.all/1` explicitly as shown above.

  ## Why the `:extensions` entry

  `use Phoenix.Swoosh` does not surface `render_body` the way most `use`s surface their API.
  Its `__using__` injects `import Phoenix.Swoosh, except: [render_body: 3]` plus a **local**
  `def render_body(email, template, assigns \\\\ %{})` that wraps the module function — so the
  bare `render_body` calls a mailer module writes resolve to a hidden local definition, not to
  an import. Mutare's in-process `use` expansion harvests the injected imports faithfully, and
  faithfully finds `render_body` excluded from them: the bare calls stay unresolved, and the
  `:render_body` family only sees qualified/aliased call forms.

  This module is therefore also a `Mutare.UseExpansion` extension. It takes over
  `use Phoenix.Swoosh` and surfaces `import Swoosh.Email` plus a **whole**
  `import Phoenix.Swoosh` — deliberately without the `except:` — standing in for the injected
  local wrapper, which forwards to `Phoenix.Swoosh.render_body/3` anyway. With it listed under
  `:extensions`, bare `render_body` calls (both arities, the wrapper's default-argument form
  included) resolve, mutate, and get their template position pinned. For the standalone
  template style (`use Phoenix.Swoosh, template_root: ...` — which also does
  `use Phoenix.View` in the caller) it additionally surfaces the `import Phoenix.View` that
  nested `use` would inject.

  It also reads one *fact* out of the `use` line: whether the mailer configured a layout
  (`layout: {MyApp.LayoutView, :email}`). That option is compile-time configuration no mutant
  can be delivered into, but whether a layout is in effect decides whether suppressing one at
  the render site is a real mutant or an equivalent one — so the expansion reports it to
  `Mutare.Phoenix.Swoosh.Layout` as the `Mutare.Phoenix.Swoosh.LayoutConfigured` marker, the
  one channel a `use` expansion has into a mutator's context.

  Without the `:extensions` entry the families still work on qualified and aliased calls, and
  `:mail_layout` works on bare setter calls too (`put_layout`/`put_new_layout` really are
  imported) — but bare `render_body` sites are neither mutated nor pinned, and `:mail_layout`'s
  `off` mutant fires only where the author wrote the `layout:` assign themselves.
  """

  @behaviour Mutare.UseExpansion

  alias Mutare.AST
  alias Mutare.Phoenix.Swoosh.{Layout, LayoutConfigured, RenderBody}

  @doc """
  This package's two phoenix_swoosh mutator families — `RenderBody`, `Layout`.

  It does **not** include the base `mutare_swoosh` families; compose those explicitly with
  `Mutare.Swoosh.all/1` when you want the full Swoosh + template surface (see the moduledoc's
  "Usage").

      iex> Mutare.Phoenix.Swoosh.all()
      [Mutare.Phoenix.Swoosh.RenderBody, Mutare.Phoenix.Swoosh.Layout]
  """
  @spec all() :: [module(), ...]
  def all, do: [RenderBody, Layout]

  # The `use Phoenix.Swoosh` override (see the moduledoc's "Why the `:extensions` entry").
  # The whole `import Phoenix.Swoosh` differs from the real injected env only on
  # `render_body/3` itself — the one name the local wrapper provides — so every other bare
  # call resolves exactly as it really does. The witness a fictional bare import would
  # normally splice (an `import` that conflicts with the real local `def` and fails the
  # compile) is dropped because `RenderBody` registers `render_body` in the macro-routing
  # registry — the two halves are a matched pair.
  @impl Mutare.UseExpansion
  def expand_use(Phoenix.Swoosh, args, _context),
    do: Mutare.UseExpansion.expand(directives(args), markers(args))

  def expand_use(_used_module, _args, _context), do: :decline

  defp directives(args) do
    base = [quote(do: import(Swoosh.Email)), quote(do: import(Phoenix.Swoosh))]

    if template_root?(args),
      do: base ++ [quote(do: import(Phoenix.View))],
      else: base
  end

  # The standalone style (`template_root:` present in the `use` opts) also runs
  # `use Phoenix.View, root: ...` in the caller, whose `__using__` injects
  # `import Phoenix.View` (phoenix_view 2.0.4) — surface it so bare `render/2,3`
  # calls in such a module resolve. The classic `view:` style injects no further imports.
  defp template_root?([opts]) when is_list(opts),
    do: not is_nil(AST.opts_get(opts, :template_root))

  defp template_root?(_args), do: false

  # The `layout:` option's *presence*, carried to `Mutare.Phoenix.Swoosh.Layout` as a marker
  # "behaviour" (see `Mutare.Phoenix.Swoosh.LayoutConfigured`). A computed value — a module
  # attribute, a function call — counts as configured: it is a layout the author put there.
  # Only a literal `layout: false`, phoenix_swoosh's own default, counts as none.
  defp markers(args), do: if(layout_configured?(args), do: [LayoutConfigured], else: [])

  defp layout_configured?([opts]) when is_list(opts) do
    case AST.opts_get(opts, :layout) do
      nil -> false
      node -> AST.literal_value(node) != {:ok, false}
    end
  end

  defp layout_configured?(_args), do: false
end
