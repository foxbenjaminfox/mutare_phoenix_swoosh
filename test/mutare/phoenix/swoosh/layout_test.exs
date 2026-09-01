defmodule Mutare.Phoenix.Swoosh.LayoutTest do
  @moduledoc """
  `:mail_layout` — removes a layout setter, pipe-aware: non-piped → the email, piped →
  `Function.identity()`. Two variant-labelled kinds: `put` (`put_layout/2`) and `put_new`
  (`put_new_layout/2`). The layout argument — tuple interior included — and
  `put_new_formats/2`'s map are pinned via the registry `:skip` routes. Works without the
  use-expansion extension: the setters are genuine exports the injected import really brings
  into scope.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.Layout

  defp layout_diffs(source), do: diffs_for(source, [Layout], :mail_layout)

  defp mailer(body) do
    "defmodule Sample.UserEmail do\n  use Phoenix.Swoosh, view: Sample.EmailView\n\n#{body}\nend\n"
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

  describe "put_new_formats/2 is pinned but never mutated" do
    test "the extension→field map is left whole and produces no removal" do
      source = mailer("  def go(e), do: put_new_formats(e, %{\"mjml\" => :html_body})")
      mutators = [Mutare.Mutators.AtomLiteral, Mutare.Mutators.StringLiteral, Layout]

      assert diffs(source, mutators) == []
    end

    test "control: without this family the map's strings are fair game" do
      source = mailer("  def go(e), do: put_new_formats(e, %{\"mjml\" => :html_body})")

      assert {"\"mjml\"", "\"mutare\""} in diffs_for(
               source,
               [Mutare.Mutators.StringLiteral],
               :string
             )
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
      assert Layout.variants() == ["put", "put_new"]
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
    end
    """

    assert_metamutant_compiles(source, [Layout])
  end
end
