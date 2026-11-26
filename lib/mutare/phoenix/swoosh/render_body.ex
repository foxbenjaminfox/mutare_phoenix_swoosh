defmodule Mutare.Phoenix.Swoosh.RenderBody do
  @moduledoc """
  `:render_body` — mutates calls that control **which email body parts are rendered**:
  `Phoenix.Swoosh.render_body/2,3`, the call that renders an email's templates onto its
  `html_body`/`text_body` fields, and the format map of `Phoenix.Swoosh.put_new_formats/2`,
  which maps template extensions to body fields. Three kinds, variant-labelled:

  **Removal** (label `remove`) — the call collapses to the email it received, so the email is
  built, addressed, and delivered with no rendered body at all:

      render_body(email, :welcome, %{name: name})  ->  email
      email |> render_body(:welcome)               ->  email

  A survivor means no test asserts the rendered body content — the mail pipeline is exercised,
  but nothing checks that `html_body`/`text_body` ever got set.

  **Atom-template narrowing** (labels `html_only` / `text_only`) — with Phoenix.Swoosh's
  standard HTML and text formats, an atom template renders both parts and the string form
  renders exactly one. The mutant checks the incoming email's format configuration before
  rendering `"welcome.html"` or `"welcome.text"` in place of `:welcome`, and raises when the
  email has different formats: no narrowing exists there, and a mutant that rendered the atom
  unchanged would survive every test. Reports show only the substituted template:

      render_body(email, :welcome, assigns)  ->  :welcome  ->  "welcome.html"
                                             ->  :welcome  ->  "welcome.text"

  A survivor means no test asserts the *other* body part. Use
  `Swoosh.TestAssertions.assert_email_sent/1` on both bodies, or a direct assertion such as
  `email.text_body =~ ...`, to kill it. Narrowing applies only to a literal atom template;
  a string or computed template gets the removal mutant alone. A bare wrapper with a
  non-`nil` or computed `formats:` option also gets only removal, since the wrapper can set
  formats after the mutant checks the email.

  **Format dropping** (label `format`) — a literal `put_new_formats/2` map with more than one
  entry loses one entry per mutant, so that extension's template stops rendering:

      put_new_formats(email, %{"html" => :html_body, "amp" => :html_body})
        ->  put_new_formats(email, %{"amp" => :html_body})
        ->  put_new_formats(email, %{"html" => :html_body})

  Format dropping can probe custom extensions. A single-entry map produces nothing: dropping
  the only format renders no body at all, duplicating the `remove` mutation.

  Suppress one kind with `# mutare:ignore[render_body:remove]` / `[render_body:html_only]` /
  `[render_body:text_only]` / `[render_body:format]`, or the family with
  `# mutare:ignore[render_body]`.

  Mutations apply only to the supported arities — `render_body/2,3` (`/2` is the
  `use`-injected wrapper's default-assigns form) and `put_new_formats/2` — so a name-matched
  call of any other arity is left alone, keeping every metamutant compiling. A piped call is
  the same call with the email piped in, and its removal collapses the stage to that email.

  ## How the three kinds relate

  At an atom-template site the removal mutant is the *weakest* of the three: any assertion that
  kills a narrowing also kills the removal, so a surviving `remove` where both narrowings also
  survive is one gap reported three times, not three gaps. It is kept because it is the only
  mutant at a string or computed template site, and the only one that also drops the assigns
  merge (a test that reads `email.assigns` rather than the bodies kills it alone).

  ## The template and format positions are pinned

  The template name (argument 1 — atom or string) is a structural identifier, not a
  computed value: a perturbed name is a missing-template crash at render time (an
  uninformative crash-kill), never a signal. `put_new_formats/2`'s extension→field map is the
  same kind of value — a perturbed extension key is a missing template, a perturbed field value
  is a crash-free but meaningless field swap. This family registers all three calls in the
  call-routing registry with those positions `:raw`, so **no** family — core value literals
  included — mutates them or anything inside them, at bare, qualified, and aliased call sites
  alike. The registry route (rather than an argument mark) is deliberate: it covers the
  position's whole subtree, and registration is also what makes the bare forms resolvable and
  witness-safe at all (see below). The `:raw` route excludes the argument subtree from
  mutation, while this family can still rewrite the argument as part of a call-level mutation.

  ## Resolution: why this family is half of a matched pair

  `use Phoenix.Swoosh` injects `import Phoenix.Swoosh, except: [render_body: 3]` plus a local
  `def render_body/2,3` wrapper — so a mailer's bare `render_body` calls resolve to a local
  definition that Mutare does not resolve. `Mutare.Phoenix.Swoosh` (listed under `:extensions`)
  overrides that `use` expansion to return a whole `import Phoenix.Swoosh` in its place.
  This family's registry entries serve two purposes:

    * the `/2` wrapper arity is not a real `Phoenix.Swoosh` export, so import reflection can
      never resolve a bare `render_body(email, :welcome)` — the registry's whole-import
      fallback is what resolves it;
    * a bare imported call normally carries a compile-time **witness** that re-imports the
      resolved provider next to the mutant — which, next to the real injected local `def`,
      is an import/local conflict that would fail the single metamutant compile. Registered
      calls have that witness dropped.

  Without the extension, bare `render_body` sites are neither mutated nor pinned (the
  injected `except:` import excludes exactly this one name); qualified and aliased
  sites work regardless.

  ## Deliberately left alone

    * **The assigns argument** is ordinary runtime data — core's families mutate the *values*
      inside it as they would anywhere (a wrong interpolated value in a body only a
      body-content assertion catches). Its *keys* are likewise subject to core's map-literal
      mutation rules, not pinned here. `Mutare.Phoenix.Swoosh.Layout` mutates the `:layout`
      assign, which configures phoenix_swoosh rather than supplying template data.
    * **Dropping an assigns entry** was considered and rejected: a template referencing the
      dropped assign raises `KeyError`/`ArgumentError` at render — a crash-kill, not a
      test of body-content assertions.
    * **Swapping a format's body field** (`"html" => :html_body` → `:text_body`) is not generated:
      the rendered html would land in `text_body` alongside whatever the text template put
      there, and which one survives depends on map ordering — a mutant whose behaviour a reader
      cannot predict from its diff.
  """

  @behaviour Mutare.Mutator
  @behaviour Mutare.CallRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.CallRouting.Call
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation
  alias Mutare.Phoenix.Swoosh.AST, as: PSAST
  alias Mutare.Phoenix.Swoosh.{FormatsConfigured, Routes}

  @default_formats %{"html" => :html_body, "text" => :text_body}

  @impl Mutare.Mutator
  @spec name() :: :render_body
  def name, do: :render_body

  # Variant vocabulary for `# mutare:ignore[render_body:<label>]`: the whole-call removal, the
  # two atom-template narrowings, and the format drop. Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(remove html_only text_only format)

  # Both real `render_body` arities with the template (argument 1) `:raw`, plus
  # `put_new_formats/2` with its map `:raw` — the structural pins. Registration is also what
  # resolves the bare `/2` wrapper form and drops the bare-import witness (see the moduledoc).
  @impl Mutare.CallRouting
  @spec call_routes() :: [Mutare.CallRouting.route()]
  def call_routes, do: Routes.render_body() ++ Routes.formats()

  # `Calls.resolved_routed_call/1` is the one reader that normalizes every written form this
  # family matches — bare (registry-resolved), qualified, aliased, and piped (a piped stage
  # arrives as the direct call with the email at argument 0).
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, context) do
    case Calls.resolved_routed_call(node) do
      %Call{module: Phoenix.Swoosh, name: :render_body, arguments: args} = call
      when length(args) in [2, 3] ->
        [removal(call) | narrowings(call, context)]

      %Call{module: Phoenix.Swoosh, name: :put_new_formats, arguments: [_email, _formats]} = call ->
        present(format_drops(call))

      _other ->
        :skip
    end
  end

  # The call collapses to its first argument (the email), in both spellings. The arity guard
  # guarantees that argument exists.
  @spec removal(Call.t()) :: Mutation.t()
  defp removal(%Call{} = call) do
    Mutation.new(PSAST.collapse_to_email(call),
      variant: "remove",
      note: "render_body removed - no test asserts the rendered body"
    )
  end

  @spec narrowings(Call.t(), Mutator.context()) :: [Mutation.t()]
  defp narrowings(call, context) do
    with false <- wrapper_formats_configured?(call, context),
         {_node, _atom} = template <- template_atom(call) do
      Enum.map(["html", "text"], &narrowed(call, template, &1))
    else
      _other -> []
    end
  end

  # A bare wrapper can set formats after the mutant inspects its input email.
  # A qualified call goes straight to Phoenix.Swoosh, so only the email's formats matter.
  defp wrapper_formats_configured?(%Call{node: {:render_body, _, _}}, context),
    do: MapSet.member?(Map.get(context, :behaviours, MapSet.new()), FormatsConfigured)

  defp wrapper_formats_configured?(%Call{}, _context), do: false

  # The template is argument 1 in both spellings, returned with its written node. `nil`,
  # `true`, and `false` are excluded — atoms, but never templates (and `render_body/3` would
  # not accept them as one).
  @spec template_atom(Call.t()) :: {Macro.t(), atom()} | nil
  defp template_atom(%Call{} = call) do
    with {_index, node} <- PSAST.arg_at(call, 1),
         {:ok, atom} when is_atom(atom) and atom not in [nil, true, false] <-
           AST.literal_value(node) do
      {node, atom}
    else
      _other -> nil
    end
  end

  # The spliced node binds the email once and checks its formats at runtime, but the report
  # shows only the template the mutant substitutes: `:welcome` -> `"welcome.html"`.
  @spec narrowed(Call.t(), {Macro.t(), atom()}, String.t()) :: Mutation.t()
  defp narrowed(
         %Call{arguments: [email, _template | assigns], rebuild: rebuild},
         {node, atom},
         extension
       ) do
    email_var = Macro.var(:render_email, __MODULE__)
    narrowed = AST.literal("#{atom}.#{extension}")
    variant = "#{extension}_only"
    call = rebuild.(:render_body, [email_var, narrowed | assigns])

    replacement =
      quote generated: true do
        unquote(email_var) = unquote(email)
        unquote(standard_formats_check(email_var, variant))
        unquote(call)
      end

    Mutation.new(replacement,
      variant: variant,
      note: "template narrowed to .#{extension} - no test asserts the #{other(extension)} body",
      attribution: Mutation.at(node, narrowed)
    )
  end

  # The string form bypasses Phoenix.Swoosh's extension list, so it narrows the atom form only
  # when both standard parts would render into their standard fields. Under any other formats
  # no narrowing exists, and rendering the atom instead would be an equivalent mutant that
  # always survives. Raising makes it an uninformative kill rather than a false survivor.
  defp standard_formats_check(email, variant) do
    message =
      "Mutare render_body:#{variant} mutant: the email does not use the standard " <>
        "\"html\"/\"text\" formats, so this narrowing does not apply"

    quote generated: true do
      case unquote(email).private do
        %{phoenix_extensions: extensions}
        when extensions not in [["html", "text"], ["text", "html"]] ->
          raise unquote(message)

        %{phoenix_extensions_to_body_key: formats}
        when formats != unquote(Macro.escape(@default_formats)) ->
          raise unquote(message)

        _ ->
          :ok
      end
    end
  end

  @spec other(String.t()) :: String.t()
  defp other("html"), do: "text"
  defp other("text"), do: "html"

  # One mutant per entry of a literal format map, each dropping that extension's render. A
  # non-literal map (a variable, a call) and a single-entry map produce nothing: the first
  # cannot be rewritten, and the second's only drop is the `remove` mutant's diff.
  @spec format_drops(Call.t()) :: [Mutation.t()]
  defp format_drops(%Call{arguments: args, rebuild: rebuild} = call) do
    with {index, node} <- PSAST.arg_at(call, 1),
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
