# Minimal stand-ins for the slices of `Swoosh.Email` and `Phoenix.Swoosh` the tests touch,
# loaded only in the test environment. `mutare_phoenix_swoosh` depends on neither
# `phoenix_swoosh` nor `swoosh` (it matches on module *names*), so these modules let the suite:
#
#   * resolve **bare imported** calls — the form `use Phoenix.Swoosh` produces — which
#     `Mutare.Transform.Imports` resolves by reflecting on the imported module's exported
#     arities, so the functions must exist with the *real* arities;
#   * expand `use Phoenix.Swoosh` **in-process** (the no-extension verdict tests), so the
#     `__using__` here mirrors the real one — the `import Phoenix.Swoosh, except:
#     [render_body: 3]` and the injected local `render_body/2,3` wrapper included;
#   * compile generated metamutants and run live-mutant semantics tests against a working
#     `render_body`.
#
# Fidelity is maintained by hand against phoenix_swoosh 1.2.1 (`lib/phoenix_swoosh.ex`) — the
# guards, clause structure, and private-map keys mirror the real module. One deliberate
# simplification, marked below: `do_render_body/4` stamps a recognisable string naming the
# template and the effective layout instead of rendering through
# `Phoenix.View.render_to_string/3`. The layout threading itself (`prepare_assigns/3` and the
# assigns override it reads) is mirrored faithfully, because the `:mail_layout` family mutates
# exactly that seam.
defmodule Swoosh.Email do
  @moduledoc false

  # The fields the real struct carries that these tests read; `mutare_swoosh`'s stub
  # (test/support/swoosh_stubs.ex there) mirrors the fuller construction surface.
  defstruct subject: "",
            from: nil,
            to: [],
            html_body: nil,
            text_body: nil,
            assigns: %{},
            private: %{}

  def new(opts \\ []), do: struct!(__MODULE__, opts)

  def from(%__MODULE__{} = email, from), do: %{email | from: from}
  def subject(%__MODULE__{} = email, subject), do: %{email | subject: subject}

  def to(%__MODULE__{} = email, recipients),
    do: %{email | to: List.wrap(recipients) ++ email.to}

  def put_private(%__MODULE__{} = email, key, value) when is_atom(key),
    do: %{email | private: Map.put(email.private, key, value)}
end

# `phoenix_view` is a *hard* dependency of phoenix_swoosh (optional: false in its hex
# metadata), so `Phoenix.View` is always loadable wherever `Phoenix.Swoosh` is — this stand-in
# keeps the `__using__` below compilable (its `use Phoenix.View` branch is macro-expanded even
# when `template_root` is nil). The real `__using__` (phoenix_view 2.0.4) also runs
# `Phoenix.View.__setup__/2`, `use Phoenix.Template`, and defines `template_not_found/2`;
# only the injected `import Phoenix.View` matters to resolution, so only it is mirrored.
defmodule Phoenix.View do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Phoenix.View
    end
  end
end

defmodule Phoenix.Swoosh do
  @moduledoc false

  # The exported arities are load-bearing: `render_body/3` is the ONLY `render_body` export —
  # the real module-level function takes no defaults, and the `/2` form exists only as the
  # `use`-injected local wrapper below. Do not "fix" this stub by adding a `/2` export: the
  # arity-2 tests specifically exercise the call-routing registry fallback that production resolution
  # relies on for the wrapper form.

  import Swoosh.Email

  defmacro __using__(opts) do
    view = Keyword.get(opts, :view)
    layout = Keyword.get(opts, :layout, false)
    template_root = Keyword.get(opts, :template_root)
    template_path = Keyword.get(opts, :template_path)
    template_namespace = Keyword.get(opts, :template_namespace)
    formats = Keyword.get(opts, :formats)

    unless view || template_root do
      raise ArgumentError, "no view or template_root was set"
    end

    view_module = if template_root, do: quote(do: __MODULE__), else: view

    quote do
      import Swoosh.Email
      import Phoenix.Swoosh, except: [render_body: 3]

      if unquote(template_root) do
        use Phoenix.View,
          root: unquote(template_root),
          path: unquote(template_path),
          namespace: unquote(template_namespace)
      end

      def render_body(email, template, assigns \\ %{}) do
        email
        |> put_new_formats(unquote(formats))
        |> put_new_layout(unquote(layout))
        |> put_new_view(unquote(view_module))
        |> Phoenix.Swoosh.render_body(template, assigns)
      end
    end
  end

  def render_body(email, template, assigns) when is_atom(template) do
    extensions(email)
    |> Enum.reduce(email, fn extension, email ->
      do_render_body(email, template_name(template, extension), extension, assigns)
    end)
  end

  def render_body(email, template, assigns) when is_binary(template) do
    case Path.extname(template) do
      "." <> extension ->
        do_render_body(email, template, extension, assigns)

      "" ->
        raise "cannot render template #{inspect(template)} without format"
    end
  end

  # Simplified from the real `do_render_body/4`: the view check, `prepare_assigns/3`'s layout
  # threading, and the extension→body-key routing are kept, but the content is a recognisable
  # stamp instead of a `Phoenix.View.render_to_string/3` call. The stamp names the layout the
  # real render would have wrapped that body part in, which is what makes the layout seam
  # observable in the live-mutant tests.
  defp do_render_body(email, template, extension, assigns) do
    assigns = Enum.into(assigns, %{})

    email =
      email
      |> put_private(:phoenix_template, template)
      |> prepare_assigns(assigns, extension)

    Map.get(email.private, :phoenix_view) ||
      raise "a view module was not specified, set one with put_view/2"

    Map.put(email, extension_to_body_key(email, extension), stamp(template, email.assigns.layout))
  end

  defp stamp(template, false), do: "rendered " <> template
  defp stamp(template, {mod, layout}), do: "rendered #{template} in #{inspect(mod)}:#{layout}"

  # Mirrors the real `prepare_assigns/3`: the per-format layout name is resolved (an atom layout
  # picks up the extension, exactly as an atom template does), and the result is merged into
  # `email.assigns` under `:layout` — the assign `Phoenix.View` renders the body inside.
  defp prepare_assigns(email, assigns, extension) do
    layout =
      case layout(email, assigns, extension) do
        {mod, layout} -> {mod, template_name(layout, extension)}
        false -> false
      end

    update_in(email.assigns, &(&1 |> Map.merge(assigns) |> Map.put(:layout, layout)))
  end

  # The render-call assigns win over the email's stored layout — phoenix_swoosh's per-render
  # override, and the seam `Mutare.Phoenix.Swoosh.Layout`'s `off` mutant writes to.
  defp layout(email, assigns, extension) do
    if extension in extensions(email) do
      case Map.fetch(assigns, :layout) do
        {:ok, layout} -> layout
        :error -> layout(email)
      end
    else
      false
    end
  end

  def put_layout(email, layout), do: do_put_layout(email, layout)

  defp do_put_layout(email, false), do: put_private(email, :phoenix_layout, false)

  defp do_put_layout(email, {mod, layout}) when is_atom(mod),
    do: put_private(email, :phoenix_layout, {mod, layout})

  defp do_put_layout(email, layout) when is_binary(layout) or is_atom(layout) do
    update_in(email.private, fn private ->
      case Map.get(private, :phoenix_layout, false) do
        {mod, _} ->
          Map.put(private, :phoenix_layout, {mod, layout})

        false ->
          raise "cannot use put_layout/2 with atom/binary when layout is false, use a tuple instead"
      end
    end)
  end

  def put_new_layout(email, layout)
      when (is_tuple(layout) and tuple_size(layout) == 2) or layout == false,
      do: update_in(email.private, &Map.put_new(&1, :phoenix_layout, layout))

  def layout(email), do: Map.get(email.private, :phoenix_layout, false)

  def put_view(email, module), do: put_private(email, :phoenix_view, module)

  def put_new_view(email, module),
    do: update_in(email.private, &Map.put_new(&1, :phoenix_view, module))

  def put_new_formats(email, nil), do: email

  def put_new_formats(email, extension_format_map) do
    update_in(email.private, fn private ->
      private
      |> Map.put_new(:phoenix_extensions, Map.keys(extension_format_map))
      |> Map.put_new(:phoenix_extensions_to_body_key, extension_format_map)
    end)
  end

  @default_mapping %{
    "htm" => :html_body,
    "html" => :html_body,
    "text" => :text_body,
    "xml" => :html_body
  }

  defp extension_to_body_key(email, extension) do
    email.private
    |> Map.get(:phoenix_extensions_to_body_key, @default_mapping)
    |> Map.get(extension, :text_body)
  end

  defp extensions(email), do: Map.get(email.private, :phoenix_extensions, ["html", "text"])

  defp template_name(name, extension) when is_atom(name),
    do: Atom.to_string(name) <> "." <> extension

  defp template_name(name, _extension) when is_binary(name), do: name
end
