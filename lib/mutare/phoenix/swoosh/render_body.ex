defmodule Mutare.Phoenix.Swoosh.RenderBody do
  @moduledoc """
  `:render_body` — mutates the calls that decide **which body parts an email renders**:
  `Phoenix.Swoosh.render_body/2,3`, the call that renders an email's templates onto its
  `html_body`/`text_body` fields, and the format map of `Phoenix.Swoosh.put_new_formats/2`,
  which decides what "both parts" even means. Three kinds, variant-labelled:

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
  `email.text_body =~ ...`, kills it. Narrowing fires only on a literal atom template; a string
  or computed template gets the removal mutant alone.

  **Format dropping** (label `format`) — a literal `put_new_formats/2` map with more than one
  entry loses one entry per mutant, so that extension's template stops rendering:

      put_new_formats(email, %{"html" => :html_body, "amp" => :html_body})
        ->  put_new_formats(email, %{"amp" => :html_body})
        ->  put_new_formats(email, %{"html" => :html_body})

  This is the custom-formats form of the same gap the narrowings probe — and the *only* form of
  it once a mailer configures `:formats`, since the narrowings' `.html`/`.text` extensions may
  not exist there (a narrowed mutant then dies as a missing-template crash: an uninformative
  kill, never a wrong survivor). A single-entry map produces nothing: dropping the only format
  renders no body at all, which is the `remove` mutant's diff, and no mutant has two homes.

  Suppress one kind with `# mutare:ignore[render_body:remove]` / `[render_body:html_only]` /
  `[render_body:text_only]` / `[render_body:format]`, or the family with
  `# mutare:ignore[render_body]`.

  Only the real effective arities fire — `render_body/2,3` (`/2` is the `use`-injected
  wrapper's default-assigns form) and `put_new_formats/2` — so a name-matched call of any other
  arity is left alone, keeping every metamutant compiling. Piped calls are removed with the
  `Elixir.Function.identity()` no-op stage (the `:Elixir`-led alias is never rewritten by alias
  resolution, so the no-op always names the real `Function.identity/1`).

  ## How the three kinds relate

  At an atom-template site the removal mutant is the *weakest* of the three: any assertion that
  kills a narrowing also kills the removal, so a surviving `remove` where both narrowings also
  survive is one gap reported three times, not three gaps. It is kept because it is the only
  mutant at a string or computed template site, and the only one that also drops the assigns
  merge (a test that reads `email.assigns` rather than the bodies kills it alone).

  ## The template and format positions are pinned

  The template name (effective argument 1 — atom or string) is a structural identifier, not a
  computed value: a perturbed name is a missing-template crash at render time (an
  uninformative crash-kill), never a signal. `put_new_formats/2`'s extension→field map is the
  same kind of value — a perturbed extension key is a missing template, a perturbed field value
  is a crash-free but meaningless field swap. This family registers all three calls in the
  macro-routing registry with those positions `:skip`, so **no** family — core value literals
  included — mutates them or anything inside them, at bare, qualified, and aliased call sites
  alike. The registry route (rather than an argument mark) is deliberate: it covers the
  position's whole subtree, and registration is also what makes the bare forms resolvable and
  witness-safe at all (see below). Keeping a position raw for everyone and then minting the one
  safe mutation there *from its owner* is exactly what the routing contract is for.

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
      map-literal judgment, not pinned here. The one assigns entry this package does speak for
      is `:layout`, which is phoenix_swoosh vocabulary rather than template data —
      `Mutare.Phoenix.Swoosh.Layout` owns it.
    * **Dropping an assigns entry** was considered and rejected: a template referencing the
      dropped assign raises `KeyError`/`ArgumentError` at render — a crash-kill, not a
      survivor question.
    * **Swapping a format's body field** (`"html" => :html_body` → `:text_body`) is not minted:
      the rendered html would land in `text_body` alongside whatever the text template put
      there, and which one survives depends on map ordering — a mutant whose behaviour a reader
      cannot predict from its diff.
  """

  @behaviour Mutare.Mutator
  @behaviour Mutare.MacroRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.MacroRouting.Call
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation
  alias Mutare.Phoenix.Swoosh.AST, as: PSAST
  alias Mutare.Phoenix.Swoosh.Routes

  @impl Mutare.Mutator
  @spec name() :: :render_body
  def name, do: :render_body

  # Variant vocabulary for `# mutare:ignore[render_body:<label>]`: the whole-call removal, the
  # two atom-template narrowings, and the format drop. Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(remove html_only text_only format)

  # Both real `render_body` arities with the template (effective argument 1) `:skip`, plus
  # `put_new_formats/2` with its map `:skip` — the structural pins. Registration is also what
  # resolves the bare `/2` wrapper form and drops the bare-import witness (see the moduledoc).
  @impl Mutare.MacroRouting
  @spec macro_routes() :: [Mutare.MacroRouting.route()]
  def macro_routes, do: Routes.render_body() ++ Routes.formats()

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

      %Call{module: Phoenix.Swoosh, name: :put_new_formats, effective_arity: 2} = call ->
        present(format_drops(call))

      _other ->
        :skip
    end
  end

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first argument
  # (the email). The arity guard guarantees a non-piped call has that argument.
  @spec removal(Call.t()) :: Mutation.t()
  defp removal(%Call{} = call) do
    Mutation.new(PSAST.collapse_to_email(call),
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
  defp template_atom(%Call{} = call) do
    with {_index, node} <- PSAST.effective_arg(call, 1),
         {:ok, atom} when is_atom(atom) and atom not in [nil, true, false] <-
           AST.literal_value(node) do
      atom
    else
      _other -> nil
    end
  end

  # Rebuild the call in its written form (`Call.rebuild` preserves bare/qualified/aliased)
  # with the atom template replaced by one of its string forms — exactly the template the
  # atom form would have rendered for that extension, so the mutant renders one real
  # template and skips the other.
  @spec narrowed(Call.t(), atom(), String.t()) :: Mutation.t()
  defp narrowed(%Call{arguments: args, rebuild: rebuild} = call, atom, extension) do
    {index, _template} = PSAST.effective_arg(call, 1)
    narrowed_args = List.replace_at(args, index, AST.literal("#{atom}.#{extension}"))

    Mutation.new(PSAST.compact(rebuild.(:render_body, narrowed_args)),
      variant: "#{extension}_only",
      note: "template narrowed to .#{extension} - no test asserts the #{other(extension)} body"
    )
  end

  @spec other(String.t()) :: String.t()
  defp other("html"), do: "text"
  defp other("text"), do: "html"

  # One mutant per entry of a literal format map, each dropping that extension's render. A
  # non-literal map (a variable, a call) and a single-entry map produce nothing: the first
  # cannot be rewritten, and the second's only drop is the `remove` mutant's diff.
  @spec format_drops(Call.t()) :: [Mutation.t()]
  defp format_drops(%Call{arguments: args, rebuild: rebuild} = call) do
    with {index, node} <- PSAST.effective_arg(call, 1),
         {:ok, {_kind, entries, wrap}} <- PSAST.container(node),
         true <- length(entries) > 1 do
      for {entry, entry_index} <- Enum.with_index(entries) do
        dropped = wrap.(List.delete_at(entries, entry_index))
        rebuilt = rebuild.(:put_new_formats, List.replace_at(args, index, dropped))

        Mutation.new(rebuilt, variant: "format", note: drop_note(entry))
      end
    else
      _other -> []
    end
  end

  @spec drop_note(Macro.t()) :: String.t()
  defp drop_note(entry) do
    case PSAST.literal_key(entry) do
      {:ok, extension} when is_binary(extension) ->
        ~s(the "#{extension}" format dropped - no test asserts that body part)

      _other ->
        "one format dropped - no test asserts that body part"
    end
  end

  @spec present([Mutation.t()]) :: :skip | [Mutation.t()]
  defp present([]), do: :skip
  defp present([_ | _] = mutations), do: mutations
end
