defmodule Mutare.Phoenix.Swoosh.LayoutTest do
  @moduledoc """
  `:mail_layout` — removes a layout setter, pipe-aware: non-piped → the email, piped →
  `Function.identity()` (`put` / `put_new`), and suppresses the layout at the render site by
  writing `layout: false` into `render_body`'s assigns (`off`), gated on a layout actually
  being in effect. The layout argument — tuple interior included — is pinned via the registry
  `:skip` routes. Setter removal works without the use-expansion extension (the setters are
  genuine exports the injected import really brings into scope); `off` needs it for everything
  but an author-written `layout:` assign.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.Layout

  @ext [extensions: [Mutare.Phoenix.Swoosh]]

  defp layout_diffs(source, opts \\ []), do: diffs_for(source, [Layout], :mail_layout, opts)

  defp mailer(body) do
    "defmodule Sample.UserEmail do\n  use Phoenix.Swoosh, view: Sample.EmailView\n\n#{body}\nend\n"
  end

  # A mailer whose `use` line configures a layout — the shape that earns the
  # `Mutare.Phoenix.Swoosh.LayoutConfigured` marker, and so the `off` mutant.
  defp branded(body) do
    "defmodule Sample.UserEmail do\n" <>
      "  use Phoenix.Swoosh, view: Sample.EmailView, layout: {Sample.LayoutView, :email}\n\n" <>
      "#{body}\nend\n"
  end

  describe "removal across written forms" do
    test "a qualified put_layout collapses to the email" do
      source =
        "defmodule M do\n  def go(e), do: Phoenix.Swoosh.put_layout(e, {LayoutV, :email})\nend\n"

      assert layout_diffs(source) == [{"Phoenix.Swoosh.put_layout(e, {LayoutV, :email})", "e"}]
    end

    test "a bare imported put_layout (use-style, no extension needed) collapses to the email" do
      assert layout_diffs(mailer("  def go(e), do: put_layout(e, {LayoutV, \"email.html\"})")) ==
               [{~s|put_layout(e, {LayoutV, "email.html"})|, "e"}]
    end

    test "an aliased put_new_layout collapses to the email" do
      source = """
      defmodule M do
        alias Phoenix.Swoosh, as: PS
        def go(e), do: PS.put_new_layout(e, {LayoutV, :email})
      end
      """

      assert layout_diffs(source) == [{"PS.put_new_layout(e, {LayoutV, :email})", "e"}]
    end

    test "a piped stage becomes the identity no-op" do
      assert layout_diffs(mailer("  def go(e), do: e |> put_layout({LayoutV, :email})")) ==
               [{"put_layout({LayoutV, :email})", "Elixir.Function.identity()"}]
    end

    test "put_layout(email, false) is removed the same way" do
      assert layout_diffs(mailer("  def go(e), do: put_layout(e, false)")) ==
               [{"put_layout(e, false)", "e"}]
    end
  end

  describe "layout suppression at the render site (off)" do
    test "a literal assigns map gains a layout: false entry" do
      source = branded("  def go(e, name), do: render_body(e, :welcome, %{name: name})")

      assert layout_diffs(source, @ext) == [
               {"render_body(e, :welcome, %{name: name})",
                "render_body(e, :welcome, %{name: name, layout: false})"}
             ]
    end

    test "a keyword assigns list gains the same entry" do
      source = branded(~s|  def go(e, user), do: render_body(e, :welcome, user: user)|)

      assert layout_diffs(source, @ext) == [
               {"render_body(e, :welcome, user: user)",
                "render_body(e, :welcome, user: user, layout: false)"}
             ]
    end

    # `Call.rebuild` would requalify the bare call at its new arity, and
    # `Phoenix.Swoosh.render_body/3` is *not* the wrapper the source called — it never sets the
    # view, so the mutant would crash instead of testing the layout. The argument is appended to
    # the node as written instead, which this test pins.
    test "the wrapper's default-assigns form gains an assigns map and stays bare" do
      source = branded("  def go(e), do: e |> render_body(:welcome)")

      assert layout_diffs(source, @ext) == [
               {"render_body(:welcome)", "render_body(:welcome, %{layout: false})"}
             ]
    end

    test "a computed assigns argument is normalised the way phoenix_swoosh normalises it" do
      source = branded("  def go(e, template, assigns), do: render_body(e, template, assigns)")

      assert layout_diffs(source, @ext) == [
               {"render_body(e, template, assigns)",
                "render_body(e, template, Elixir.Map.put(Elixir.Enum.into(assigns, %{}), :layout, false))"}
             ]
    end

    test "an author-written layout assign is turned off with no marker needed" do
      source = """
      defmodule M do
        def go(e), do: Phoenix.Swoosh.render_body(e, :welcome, %{layout: {LayoutV, :promo}})
      end
      """

      assert layout_diffs(source) == [
               {"Phoenix.Swoosh.render_body(e, :welcome, %{layout: {LayoutV, :promo}})",
                "Phoenix.Swoosh.render_body(e, :welcome, %{layout: false})"}
             ]
    end

    test "an already-false layout assign yields nothing (an equivalent mutant)" do
      source = branded("  def go(e), do: render_body(e, :welcome, %{layout: false})")

      assert layout_diffs(source, @ext) == []
    end

    test "no layout in effect yields nothing" do
      source = mailer("  def go(e, name), do: render_body(e, :welcome, %{name: name})")

      assert layout_diffs(source, @ext) == []
    end

    test "use Phoenix.Swoosh, layout: false counts as no layout" do
      source = """
      defmodule Sample.UserEmail do
        use Phoenix.Swoosh, view: Sample.EmailView, layout: false

        def go(e, name), do: render_body(e, :welcome, %{name: name})
      end
      """

      assert layout_diffs(source, @ext) == []
    end

    test "without the extension a bare render_body site is out of reach" do
      source = branded("  def go(e, name), do: render_body(e, :welcome, %{name: name})")

      assert layout_diffs(source) == []
    end
  end

  describe "the structural :skip pin on the layout argument" do
    test "core's value families leave the tuple interior alone when this family is enabled" do
      source = mailer("  def go(e), do: put_layout(e, {LayoutV, \"email.html\"})")
      mutators = [Mutare.Mutators.AtomLiteral, Mutare.Mutators.StringLiteral, Layout]

      assert diffs(source, mutators) ==
               [{:mail_layout, ~s|put_layout(e, {LayoutV, "email.html"})|, "e"}]
    end

    test "a flippable false layout is pinned too" do
      source = mailer("  def go(e), do: put_new_layout(e, false)")

      assert diffs(source, [Mutare.Mutators.BooleanLiteral, Layout]) ==
               [{:mail_layout, "put_new_layout(e, false)", "e"}]
    end

    test "control: without this family the sentinel mutants do fire inside the tuple" do
      source = mailer("  def go(e), do: put_layout(e, {LayoutV, \"email.html\"})")

      assert diffs_for(source, [Mutare.Mutators.StringLiteral], :string) ==
               [{"\"email.html\"", "\"\""}, {"\"email.html\"", "\"mutare\""}]
    end
  end

  describe "scope" do
    test "a wrong-arity qualified setter is left alone" do
      one = "defmodule M do\n  def go(e), do: Phoenix.Swoosh.put_layout(e)\nend\n"
      three = "defmodule M do\n  def go(e), do: Phoenix.Swoosh.put_layout(e, V, :email)\nend\n"

      assert layout_diffs(one) == []
      assert layout_diffs(three) == []
    end

    test "does not touch a same-named local put_layout (no use, no import)" do
      source = """
      defmodule M do
        def go(e), do: put_layout(e, {LayoutV, :email})
        def put_layout(e, _layout), do: e
      end
      """

      assert layout_diffs(source) == []
    end

    test "leaves put_view and the layout getter untouched" do
      source = mailer("  def go(e), do: e |> put_view(OtherView) |> layout()")

      assert layout_diffs(source) == []
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      assert Layout.mutate(Mutare.AST.parse!("Phoenix.Swoosh.put_layout(e, {LayoutV, :email})")) ==
               :skip
    end
  end

  describe "variant labels (# mutare:ignore[mail_layout:<kind>])" do
    test "the declared vocabulary" do
      assert Layout.variants() == ["put", "put_new", "off"]
    end

    test "a qualified directive suppresses one kind and leaves the other live" do
      source =
        mailer("""
          def go(e) do
            e
            |> put_layout({LayoutV, :email}) # mutare:ignore[mail_layout:put]
            |> put_new_layout({LayoutV, :email})
          end
        """)

      result = Mutare.transform_string(source, mutators: [Layout])

      assert Enum.map(result.mutants, &{&1.variant, &1.ignored}) ==
               [{["put"], true}, {["put_new"], false}]
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule LayoutCompileDemo do
      use Phoenix.Swoosh, view: Sample.EmailView, layout: {DefaultLayout, :email}

      def branded(email) do
        email
        |> put_layout({BrandLayout, "email.html"})
        |> render_body(:welcome, %{})
      end

      def bare(email), do: put_new_layout(email, false)

      def computed(email, template, assigns), do: render_body(email, template, assigns)

      def defaulted(email), do: render_body(email, :welcome)
    end
    """

    assert_metamutant_compiles(source, [Layout], @ext)
  end
end
