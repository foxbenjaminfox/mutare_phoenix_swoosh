defmodule Mutare.Phoenix.Swoosh.RenderBody do
  @moduledoc """
  `:render_body` — mutates `Phoenix.Swoosh.render_body/2,3`, the call that renders an email's
  templates onto its `html_body`/`text_body` fields. Two kinds, variant-labelled:

  **Removal** (label `remove`) — the call collapses to the email it received, so the email is
  built, addressed, and delivered with no rendered body at all:

      render_body(email, :welcome, %{name: name})  ->  email
      email |> render_body(:welcome)               ->  Elixir.Function.identity()

  A survivor means no test asserts the rendered body content — the mail pipeline is exercised,
  but nothing checks that `html_body`/`text_body` ever got set.

  **Atom-template narrowing** (labels `html_only` / `text_only`) — an atom template renders
  *both* the `.html` and the `.text` template; the string form renders exactly one. Narrowing
  the literal atom to each string form drops the other body part:

      render_body(email, :welcome, assigns)  ->  render_body(email, "welcome.html", assigns)
                                             ->  render_body(email, "welcome.text", assigns)

  A survivor means no test asserts the *other* body part — the classic "the text part broke and
  nobody noticed" gap. `Swoosh.TestAssertions.assert_email_sent/1` on both bodies, or a direct
  `email.text_body =~ ...`, kills it. One caveat: under a custom `:formats` map (`use
  Phoenix.Swoosh, formats: %{...}`) the default `.html`/`.text` extensions may not exist, and
  the narrowed mutant then dies as a missing-template crash — an uninformative kill, never a
  wrong survivor. Narrowing fires only on a literal atom template; a string or computed
  template gets the removal mutant alone.

  Suppress one kind with `# mutare:ignore[render_body:remove]` / `[render_body:html_only]` /
  `[render_body:text_only]`, or the family with `# mutare:ignore[render_body]`.

  Only the real effective arities fire — `render_body/2,3` (`/2` is the `use`-injected
  wrapper's default-assigns form) — so a name-matched call of any other arity is left alone,
  keeping every metamutant compiling. Piped calls are removed with the
  `Elixir.Function.identity()` no-op stage (the `:Elixir`-led alias is never rewritten by alias
  resolution, so the no-op always names the real `Function.identity/1`).

  ## The template position is pinned

  The template name (effective argument 1 — atom or string) is a structural identifier, not a
  computed value: a perturbed name is a missing-template crash at render time (an
  uninformative crash-kill), never a signal. This family registers both arities in the
  macro-routing registry with that position `:skip`, so **no** family — core value literals
  included — mutates the template or anything inside it, at bare, qualified, and aliased call
  sites alike. The registry route (rather than an argument mark) is deliberate: it covers the
  position's whole subtree, and registration is also what makes the bare forms resolvable and
  witness-safe at all (see below).

  ## Resolution: why this family is half of a matched pair

  `use Phoenix.Swoosh` injects `import Phoenix.Swoosh, except: [render_body: 3]` plus a local
  `def render_body/2,3` wrapper — so a mailer's bare `render_body` calls resolve to a local
  definition invisible to Mutare. `Mutare.Phoenix.Swoosh` (listed under `:extensions`)
  overrides that `use` to surface a whole `import Phoenix.Swoosh` in its place; this family's
  registry entries then complete the picture twice over:

    * the `/2` wrapper arity is not a real `Phoenix.Swoosh` export, so import reflection can
      never resolve a bare `render_body(email, :welcome)` — the registry's whole-import
      fallback is what resolves it;
    * a bare imported call normally carries a compile-time **witness** that re-imports the
      believed provider next to the mutant — which, next to the real injected local `def`,
      is an import/local conflict that would fail the single metamutant compile. Registered
      calls have that witness dropped.

  Without the extension, bare `render_body` sites are neither mutated nor pinned (the
  faithfully-harvested `except:` import excludes exactly this one name); qualified and aliased
  sites work regardless.

  ## Deliberately left alone

    * **The assigns argument** is ordinary runtime data — core's families mutate the *values*
      inside it as they would anywhere (a wrong interpolated value in a body only a
      body-content assertion catches). Its *keys* are likewise left to core's uniform
      map-literal judgment, not pinned here.
    * **Dropping an assigns entry** was considered and rejected: a template referencing the
      dropped assign raises `KeyError`/`ArgumentError` at render — a crash-kill, not a
      survivor question.
  """

  @behaviour Mutare.Mutator
  @behaviour Mutare.MacroRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.MacroRouting.Call
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation

  @impl Mutare.Mutator
  @spec name() :: :render_body
  def name, do: :render_body

  # Variant vocabulary for `# mutare:ignore[render_body:<label>]`: the whole-call removal, and
  # the two atom-template narrowings. Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(remove html_only text_only)

  # Both real effective arities, template (effective argument 1) `:skip` — the structural pin —
  # and everything else ordinary runtime. Registration is also what resolves the bare `/2`
  # wrapper form and drops the bare-import witness (see the moduledoc).
  @impl Mutare.MacroRouting
  @spec macro_routes() :: [Mutare.MacroRouting.route()]
  def macro_routes do
    [
      {Phoenix.Swoosh, :render_body, 2, [:expression, :skip]},
      {Phoenix.Swoosh, :render_body, 3, [:expression, :skip, :expression]}
    ]
  end

  # Never fires node-locally: whether removal returns the first arg (non-piped) or
  # `Function.identity()` (piped) depends on pipe context, unknowable from the node.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # `Calls.resolved_macro_call/1` is the one reader that normalizes every written form this
  # family matches — bare (registry-resolved), qualified, aliased, and piped — and carries the
  # pipe context itself, so the threaded `context` is not consulted.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, _context) do
    case Calls.resolved_macro_call(node) do
      %Call{module: Phoenix.Swoosh, name: :render_body, effective_arity: arity} = call
      when arity in [2, 3] ->
        [removal(call) | narrowings(call)]

      _other ->
        :skip
    end
  end

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first argument
  # (the email). The arity guard guarantees a non-piped call has that argument, so the
  # `:unpiped` clause only ever sees the non-empty list its spec promises.
  @spec removal(Call.t()) :: Mutation.t()
  defp removal(%Call{pipe_mode: :piped}),
    do: removal_mutation(AST.absolute_call([:Function], :identity, []))

  defp removal(%Call{pipe_mode: :unpiped, arguments: [email | _rest]}),
    do: removal_mutation(email)

  @spec removal_mutation(Macro.t()) :: Mutation.t()
  defp removal_mutation(node) do
    Mutation.new(node,
      variant: "remove",
      note: "render_body removed - no test asserts the rendered body"
    )
  end

  # The two narrowings, only for a literal plain-atom template (`:welcome` — the render-both
  # form). A string template already renders one part, and a computed template can't be
  # narrowed by rewriting; both get the removal mutant alone.
  @spec narrowings(Call.t()) :: [Mutation.t()]
  defp narrowings(%Call{} = call) do
    case template_atom(call) do
      nil -> []
      atom -> Enum.map(["html", "text"], &narrowed(call, atom, &1))
    end
  end

  # The template is effective argument 1, so its visible index shifts under a pipe. `nil`,
  # `true`, and `false` are excluded — atoms, but never templates (and `render_body/3` would
  # not accept them as one).
  @spec template_atom(Call.t()) :: atom() | nil
  defp template_atom(%Call{arguments: args, pipe_mode: pipe_mode}) do
    case args |> Enum.at(Mutator.visible_index(1, pipe_mode)) |> AST.literal_value() do
      {:ok, atom} when is_atom(atom) and atom not in [nil, true, false] -> atom
      _other -> nil
    end
  end

  # Rebuild the call in its written form (`Call.rebuild` preserves bare/qualified/aliased)
  # with the atom template replaced by one of its string forms — exactly the template the
  # atom form would have rendered for that extension, so the mutant renders one real
  # template and skips the other.
  @spec narrowed(Call.t(), atom(), String.t()) :: Mutation.t()
  defp narrowed(%Call{arguments: args, pipe_mode: pipe_mode, rebuild: rebuild}, atom, extension) do
    index = Mutator.visible_index(1, pipe_mode)
    narrowed_args = List.replace_at(args, index, AST.literal("#{atom}.#{extension}"))

    Mutation.new(compact(rebuild.(:render_body, narrowed_args)),
      variant: "#{extension}_only",
      note: "template narrowed to .#{extension} - no test asserts the #{other(extension)} body"
    )
  end

  @spec other(String.t()) :: String.t()
  defp other("html"), do: "text"
  defp other("text"), do: "html"

  # `Call.rebuild` reuses the visible argument nodes, whose meta still describes the original
  # source layout; mixed with the fresh, position-free template literal, Sourceror renders the
  # piped rebuild across several lines. Dropping the position keys from the rebuilt subtree
  # renders the mutant compactly; the value-shaping keys (`:delimiter`, `:format`, `:token`)
  # stay.
  @position_keys [:line, :column, :end_of_expression, :newlines, :closing]

  @spec compact(Macro.t()) :: Macro.t()
  defp compact(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, Keyword.drop(meta, @position_keys), args}
      other -> other
    end)
  end
end
