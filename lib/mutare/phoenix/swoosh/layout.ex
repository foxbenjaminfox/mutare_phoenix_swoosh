defmodule Mutare.Phoenix.Swoosh.Layout do
  @moduledoc """
  `:mail_layout` — mutates the seam that decides **which layout wraps the rendered body**.

  Two kinds, variant-labelled:

  **Setter removal** (labels `put` / `put_new`) — a `Phoenix.Swoosh` layout-configuration call
  collapses to the email it would have returned:

      put_layout(email, {LayoutView, "email.html"})      ->  email
      put_new_layout(email, {LayoutView, :email})        ->  email
      email |> put_layout({LayoutView, "email.html"})    ->  Elixir.Function.identity()

  `put` (`put_layout/2`) leaves the email with its previous layout, usually the
  `use`-configured one; `put_new` (`put_new_layout/2`) leaves the layout unset and the body
  renders bare. Either way the templates still render and the email still ships.

  **Layout suppression at the render site** (label `off`) — `render_body/2,3` takes the layout
  from its assigns when one is given there (phoenix_swoosh's per-render override), so setting
  it to `false` renders the body with no layout at all:

      render_body(email, :welcome, %{name: name})
        ->  render_body(email, :welcome, %{name: name, layout: false})
      render_body(email, :welcome, %{layout: {LayoutView, :promo}})
        ->  render_body(email, :welcome, %{layout: false})
      email |> render_body(:welcome)
        ->  email |> render_body(:welcome, %{layout: false})

  A survivor of either kind means no test asserts which layout wrapped the rendered body — the
  branded wrapper, the unsubscribe footer, the logo header. Suppress one kind with
  `# mutare:ignore[mail_layout:put]` / `[mail_layout:put_new]` / `[mail_layout:off]`, or the
  family with `# mutare:ignore[mail_layout]`.

  ## Why the render site, and when `off` fires

  Real mailers rarely call `put_layout` at all: the idiomatic place for a layout is the `use`
  line (`use Phoenix.Swoosh, view: MyApp.EmailView, layout: {MyApp.LayoutView, :email}`), which
  is compile-time configuration Mutare cannot reach (see the README's "What's deliberately out
  of scope"). Without the `off` mutant this family would have nothing to say about the majority
  of layout-using mailers. The assigns override is the runtime seam that same configuration
  flows through, so mutating it reaches the layout wherever it was configured.

  Suppressing a layout that was never in effect is an equivalent mutant, and this package does
  not mint those, so `off` fires only when a layout demonstrably *is* in effect at the site:

    * the mailer's `use Phoenix.Swoosh` line configured one — reported to this family by
      `Mutare.Phoenix.Swoosh.LayoutConfigured`, the marker the package's `:extensions` entry
      injects while expanding that `use`; or
    * the call's own assigns literal carries a truthy `layout:` entry, which needs no marker
      because the author wrote the layout right there.

  Without the `:extensions` entry there is no marker, so `off` fires on the second case only.
  A mailer that configures its layout by calling `put_layout` gets the `put` removal at that
  call instead — the same gap, owned once.

  ## Written forms and arities

  Only the real arities fire — both setters are `/2`, and `render_body` is `/2,3` (`/2` is the
  `use`-injected wrapper's default-assigns form) — so a name-matched call of any other arity is
  left alone, keeping every metamutant compiling. Piped setter calls are removed with the
  `Elixir.Function.identity()` no-op stage.

  Matches direct (`Phoenix.Swoosh.put_layout(...)`), aliased, and bare-imported calls. Unlike
  `:render_body`, the setters' bare form needs no `use`-expansion override: they are genuine
  `Phoenix.Swoosh` exports that the injected `import Phoenix.Swoosh, except: [render_body: 3]`
  really does bring into scope, so Mutare's in-process `use` expansion resolves them on its
  own. Bare `render_body` calls do need it, which is why this family declares the same
  `render_body` routes `:render_body` does — from one internal routes helper, so the fact has a
  single home. Identical declarations from two providers coalesce in the registry, so either
  family alone still resolves and pins the call.

  ## The layout argument is pinned

  The layout value — `{LayoutView, "email.html"}`, `{LayoutView, :email}`, a bare name once a
  layout view is set, or `false` — is structural configuration, not a computed value: a
  perturbed template name inside the tuple is a missing-template crash at render (an
  uninformative kill), and a flipped `false` is a `put_layout`-contract raise. Both setters'
  argument 1 is registered `:skip` in the macro-routing registry, which covers the position's
  **whole subtree** (the string inside the tuple included) against every family — the reason a
  registry route is used here rather than an argument mark, which pins only the argument's own
  node.

  The same value written as a `layout:` *assign* is **not** pinned: it sits inside the assigns
  map, which stays ordinary runtime data so core's value families can keep mutating the
  template variables around it. Core will therefore perturb an assigns layout tuple into
  missing-template crash-kills, as it would anywhere. A `:skip_arguments` mark cannot fix that
  — it pins the argument's own node, not the subtree under it — and routing the whole assigns
  argument `:skip` would cost every useful mutation inside it. Named rather than hidden: at
  such a site, `# mutare:ignore` is the tool.

  ## Deliberately left alone

    * `put_view/2` and `put_new_view/2` are not mutated: removing them leaves the render with
      no view module in the standalone flow, and `render_body` then raises ("a view module was
      not specified") — a crash-kill, not a signal. There is nothing to pin either: their
      argument is a module alias, which no value family mutates. `layout/1` is a getter with no
      seam.
    * **Narrowing a layout name** (`{LayoutView, :email}` → `{LayoutView, "email.html"}`, so
      both body parts render inside the *html* layout) is the exact analogue of `:render_body`'s
      template narrowing and probes a real gap — no test asserts the text part's wrapper. It is
      deferred rather than rejected: whether an html layout renders around a text body cleanly
      or raises inside `Phoenix.View` is a fact about the real library this package does not
      yet verify, and a mutant whose kill mode is unknown is not worth minting. The sites are
      also vanishingly rare (see "Why the render site" above).
    * **Swapping `put_new_layout` for `put_layout`** (and the same for the view setters) is the
      phoenix_swoosh analogue of `Mutare.Mutators.MapKeyword`'s `put ↔ put_new` lattice and
      would collide with nothing. It is not minted because the only `put_new_layout` call in a
      typical mailer is the one the `use` wrapper generates — macro-generated code, which
      Mutare does not mutate.
  """

  @behaviour Mutare.Mutator
  @behaviour Mutare.MacroRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.MacroRouting.Call
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation
  alias Mutare.Phoenix.Swoosh.AST, as: PSAST
  alias Mutare.Phoenix.Swoosh.LayoutConfigured
  alias Mutare.Phoenix.Swoosh.Routes

  @impl Mutare.Mutator
  @spec name() :: :mail_layout
  def name, do: :mail_layout

  # Variant vocabulary for `# mutare:ignore[mail_layout:<label>]`: which setter was removed, or
  # the render-site suppression. Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(put put_new off)

  # Argument 1 of each setter is `:skip` — the structural pin over the whole layout subtree —
  # and the `render_body` routes are declared identically to `:render_body`'s so this family
  # resolves and mutates the render site on its own (see the moduledoc).
  @impl Mutare.MacroRouting
  @spec macro_routes() :: [Mutare.MacroRouting.route()]
  def macro_routes, do: Routes.layout_setters() ++ Routes.render_body()

  # Never fires node-locally: whether removal returns the first arg (non-piped) or
  # `Function.identity()` (piped) depends on pipe context, and `off` depends on the enclosing
  # module's `use` line — neither is knowable from the node.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # `Calls.resolved_macro_call/1` normalizes every written form (bare, qualified, aliased,
  # piped) and carries the pipe context itself; the registered arities are matched in the head,
  # so a wrong-arity qualified call — unregistered, hence unstamped — falls to `:skip`.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, context) do
    case Calls.resolved_macro_call(node) do
      %Call{module: Phoenix.Swoosh, name: name, effective_arity: 2} = call
      when name in [:put_layout, :put_new_layout] ->
        [removal(call, label(name))]

      %Call{module: Phoenix.Swoosh, name: :render_body, effective_arity: arity} = call
      when arity in [2, 3] ->
        present(suppressions(node, call, layout_configured?(context)))

      _other ->
        :skip
    end
  end

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first argument
  # (the email). The arity match guarantees a non-piped call has that argument.
  @spec removal(Call.t(), String.t()) :: Mutation.t()
  defp removal(%Call{} = call, label) do
    Mutation.new(PSAST.collapse_to_email(call),
      variant: label,
      note: "layout call removed - no test asserts the rendered layout"
    )
  end

  @spec label(atom()) :: String.t()
  defp label(:put_layout), do: "put"
  defp label(:put_new_layout), do: "put_new"

  # The marker `Mutare.Phoenix.Swoosh` injects for a mailer whose `use` line set a layout. The
  # behaviour set is absent outside any module and empty in a plain one, so the default is "no
  # layout in effect" — the conservative direction, which mints nothing.
  @spec layout_configured?(Mutator.context()) :: boolean()
  defp layout_configured?(context) do
    context
    |> Map.get(:behaviours, MapSet.new())
    |> MapSet.member?(LayoutConfigured)
  end

  # `render_body/3` with a literal assigns container: replace a truthy `layout:` entry's value,
  # or add the entry when the `use` line configured a layout. An already-`false` entry yields
  # nothing — suppressing a layout that is already off is an equivalent mutant.
  @spec suppressions(Macro.t(), Call.t(), boolean()) :: [Mutation.t()]
  defp suppressions(_node, %Call{effective_arity: 3} = call, configured?) do
    {index, assigns} = PSAST.effective_arg(call, 2)

    case PSAST.container(assigns) do
      {:ok, {_kind, entries, wrap}} ->
        entries
        |> override_entries(configured?)
        |> Enum.map(&suppression(call, index, wrap.(&1)))

      :error ->
        if configured?, do: [suppression(call, index, forced_off(assigns))], else: []
    end
  end

  # The `use`-injected wrapper's default-assigns form: there is no assigns argument to rewrite,
  # so the mutant supplies one. The argument is appended to the node as written rather than
  # through `Call.rebuild`, which would requalify the bare call at its new arity and so call
  # `Phoenix.Swoosh.render_body/3` *instead of* the wrapper that sets the view (see
  # `Mutare.Phoenix.Swoosh.AST.append_argument/2`).
  defp suppressions(node, %Call{effective_arity: 2}, true) do
    case PSAST.append_argument(node, PSAST.map([PSAST.entry(:layout, false)])) do
      nil -> []
      appended -> [mutation(appended)]
    end
  end

  defp suppressions(_node, %Call{effective_arity: 2}, false), do: []

  # At most one mutant per call: the author's own `layout:` entry turned off, or — failing that
  # and only under a `use`-configured layout — a fresh one appended.
  @spec override_entries([Macro.t()], boolean()) :: [[Macro.t()]]
  defp override_entries(entries, configured?) do
    case Enum.find_index(entries, &(PSAST.key(&1) == :layout)) do
      nil ->
        if configured?, do: [entries ++ [PSAST.entry(:layout, false)]], else: []

      index ->
        entry = Enum.at(entries, index)

        if PSAST.false_literal?(value(entry)),
          do: [],
          else: [List.replace_at(entries, index, PSAST.replace_value(entry, AST.literal(false)))]
    end
  end

  defp value({_key, value}), do: value

  # A computed assigns argument (a variable, a call) is normalized the way phoenix_swoosh
  # normalizes it itself — `Enum.into(assigns, %{})` accepts the map and the keyword list the
  # real `render_body/3` accepts — and then carries the override. Absolute aliases, so no alias
  # in the target source can redirect either call.
  @spec forced_off(Macro.t()) :: Macro.t()
  defp forced_off(assigns) do
    normalized = AST.absolute_call([:Enum], :into, [assigns, PSAST.empty_map()])

    AST.absolute_call([:Map], :put, [normalized, AST.literal(:layout), AST.literal(false)])
  end

  @spec suppression(Call.t(), non_neg_integer(), Macro.t()) :: Mutation.t()
  defp suppression(%Call{arguments: args, rebuild: rebuild}, index, assigns) do
    mutation(rebuild.(:render_body, List.replace_at(args, index, assigns)))
  end

  @spec mutation(Macro.t()) :: Mutation.t()
  defp mutation(rebuilt) do
    Mutation.new(PSAST.compact(rebuilt),
      variant: "off",
      note: "layout suppressed - no test asserts the rendered layout"
    )
  end

  @spec present([Mutation.t()]) :: :skip | [Mutation.t()]
  defp present([]), do: :skip
  defp present([_ | _] = mutations), do: mutations
end
