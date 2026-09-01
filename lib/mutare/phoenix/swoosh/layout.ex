defmodule Mutare.Phoenix.Swoosh.Layout do
  @moduledoc """
  `:mail_layout` — removes a `Phoenix.Swoosh` layout-configuration call, collapsing it to the
  email it would have returned:

      put_layout(email, {LayoutView, "email.html"})      ->  email
      put_new_layout(email, {LayoutView, :email})        ->  email
      email |> put_layout({LayoutView, "email.html"})    ->  Elixir.Function.identity()

  Both layout setters are one family with two variant labels: `put` (`put_layout/2` — the
  email keeps its previous layout, usually the `use`-configured one) and `put_new`
  (`put_new_layout/2` — the layout stays unset and the body renders bare). Either way the
  templates still render and the email still ships; a survivor means no test asserts which
  layout wrapped the rendered body. Suppress one kind with `# mutare:ignore[mail_layout:put]`
  / `[mail_layout:put_new]`, or the family with `# mutare:ignore[mail_layout]`.

  Only the real arity fires — both setters are `/2` — so a name-matched call of any other
  arity (reachable only by an explicit qualifier) is left alone, keeping every metamutant
  compiling. Piped calls are removed with the `Elixir.Function.identity()` no-op stage.

  Matches direct (`Phoenix.Swoosh.put_layout(...)`), aliased, and bare-imported calls. Unlike
  `:render_body`, the bare form needs no `use`-expansion override: both setters are genuine
  `Phoenix.Swoosh` exports that the injected `import Phoenix.Swoosh, except: [render_body: 3]`
  really does bring into scope, so Mutare's in-process `use` expansion resolves them on its
  own.

  ## The layout argument is pinned

  The layout value — `{LayoutView, "email.html"}`, `{LayoutView, :email}`, a bare name once a
  layout view is set, or `false` — is structural configuration, not a computed value: a
  perturbed template name inside the tuple is a missing-template crash at render (an
  uninformative kill), and a flipped `false` is a `put_layout`-contract raise. Both setters'
  argument 1 is registered `:skip` in the macro-routing registry, which covers the position's
  **whole subtree** (the string inside the tuple included) against every family — the reason a
  registry route is used here rather than an argument mark, which pins only the argument's own
  node.

  `put_new_formats/2` gets the same defensive registration — its extension→field map
  (`%{"html" => :html_body, ...}`) is structural configuration whose perturbation is a
  missing-template crash — but **no removal mutant**: removing it falls back to the default
  `.html`/`.text` extensions, which an app that configured custom formats typically doesn't
  ship templates for, so the removal would mostly be a crash-kill, not a survivor question.

  ## Deliberately left alone

  `put_view/2` and `put_new_view/2` are not mutated: removing them leaves the render with no
  view module in the standalone flow, and `render_body` then raises ("a view module was not
  specified") — a crash-kill, not a signal. There is nothing to pin either: their argument is
  a module alias, which no value family mutates. `layout/1` is a getter with no seam.
  """

  @behaviour Mutare.Mutator
  @behaviour Mutare.MacroRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.MacroRouting.Call
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation

  @impl Mutare.Mutator
  @spec name() :: :mail_layout
  def name, do: :mail_layout

  # Variant vocabulary for `# mutare:ignore[mail_layout:<label>]`: which setter was removed.
  # Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(put put_new)

  # Argument 1 of each call is `:skip` — the structural pin over the whole layout/formats
  # subtree. The `put_new_formats` entry is defensive only; this family never mutates it.
  @impl Mutare.MacroRouting
  @spec macro_routes() :: [Mutare.MacroRouting.route()]
  def macro_routes do
    [
      {Phoenix.Swoosh, :put_layout, 2, [:expression, :skip]},
      {Phoenix.Swoosh, :put_new_layout, 2, [:expression, :skip]},
      {Phoenix.Swoosh, :put_new_formats, 2, [:expression, :skip]}
    ]
  end

  # Never fires node-locally: whether removal returns the first arg (non-piped) or
  # `Function.identity()` (piped) depends on pipe context, unknowable from the node.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # `Calls.resolved_macro_call/1` normalizes every written form (bare, qualified, aliased,
  # piped) and carries the pipe context itself; the registered arity (2) is matched in the
  # head, so a wrong-arity qualified call — unregistered, hence unstamped — falls to `:skip`.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, _context) do
    case Calls.resolved_macro_call(node) do
      %Call{module: Phoenix.Swoosh, name: name, effective_arity: 2} = call
      when name in [:put_layout, :put_new_layout] ->
        [removal(call, label(name))]

      _other ->
        :skip
    end
  end

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first argument
  # (the email). The arity match guarantees a non-piped call has that argument.
  @spec removal(Call.t(), String.t()) :: Mutation.t()
  defp removal(%Call{pipe_mode: :piped}, label),
    do: removal_mutation(AST.absolute_call([:Function], :identity, []), label)

  defp removal(%Call{pipe_mode: :unpiped, arguments: [email | _rest]}, label),
    do: removal_mutation(email, label)

  @spec removal_mutation(Macro.t(), String.t()) :: Mutation.t()
  defp removal_mutation(node, label) do
    Mutation.new(node,
      variant: label,
      note: "layout call removed - no test asserts the rendered layout"
    )
  end

  @spec label(atom()) :: String.t()
  defp label(:put_layout), do: "put"
  defp label(:put_new_layout), do: "put_new"
end
