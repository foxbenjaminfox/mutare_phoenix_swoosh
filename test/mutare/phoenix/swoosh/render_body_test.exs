defmodule Mutare.Phoenix.Swoosh.RenderBodyTest do
  @moduledoc """
  `:render_body` — whole-call removal (non-piped → the email, piped → `Function.identity()`)
  plus atom-template narrowing to the two string forms, across bare (`use`-style, both
  wrapper arities), qualified, aliased, and piped call sites; the template position's
  registry `:skip` pin with its control; variant labels; and the arity/locality guards.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.RenderBody

  @ext [extensions: [Mutare.Phoenix.Swoosh]]

  defp rb_diffs(source, opts \\ @ext), do: diffs_for(source, [RenderBody], :render_body, opts)

  defp mailer(body) do
    "defmodule Sample.UserEmail do\n  use Phoenix.Swoosh, view: Sample.EmailView\n\n#{body}\nend\n"
  end

  describe "removal and narrowing across written forms" do
    test "a qualified atom-template call: removal plus both narrowings" do
      source =
        "defmodule M do\n  def go(e, a), do: Phoenix.Swoosh.render_body(e, :welcome, a)\nend\n"

      assert rb_diffs(source) == [
               {"Phoenix.Swoosh.render_body(e, :welcome, a)", "e"},
               {"Phoenix.Swoosh.render_body(e, :welcome, a)",
                "Phoenix.Swoosh.render_body(e, \"welcome.html\", a)"},
               {"Phoenix.Swoosh.render_body(e, :welcome, a)",
                "Phoenix.Swoosh.render_body(e, \"welcome.text\", a)"}
             ]
    end

    test "an aliased call is recognised" do
      source = """
      defmodule M do
        alias Phoenix.Swoosh, as: PS
        def go(e, a), do: PS.render_body(e, "welcome.html", a)
      end
      """

      assert rb_diffs(source) == [{~s|PS.render_body(e, "welcome.html", a)|, "e"}]
    end

    test "a bare use-style call at the wrapper's full arity" do
      assert rb_diffs(mailer("  def go(e, a), do: render_body(e, \"welcome.html\", a)")) ==
               [{~s|render_body(e, "welcome.html", a)|, "e"}]
    end

    test "a bare use-style call at the wrapper's default-assigns arity (/2)" do
      assert rb_diffs(mailer("  def go(e), do: render_body(e, :welcome)")) == [
               {"render_body(e, :welcome)", "e"},
               {"render_body(e, :welcome)", ~s|render_body(e, "welcome.html")|},
               {"render_body(e, :welcome)", ~s|render_body(e, "welcome.text")|}
             ]
    end

    test "a piped stage becomes the identity no-op" do
      assert rb_diffs(mailer("  def go(e), do: e |> render_body(:welcome, %{})")) == [
               {"render_body(:welcome, %{})", "Elixir.Function.identity()"},
               {"render_body(:welcome, %{})", ~s|render_body("welcome.html", %{})|},
               {"render_body(:welcome, %{})", ~s|render_body("welcome.text", %{})|}
             ]
    end

    test "a mid-chain stage is still removed" do
      body = "  def go(e), do: e |> render_body(\"welcome.html\", %{}) |> deliver()"

      assert rb_diffs(mailer(body <> "\n  defp deliver(e), do: e")) ==
               [{~s|render_body("welcome.html", %{})|, "Elixir.Function.identity()"}]
    end
  end

  describe "narrowing fires only on a literal plain atom" do
    test "a string template gets the removal mutant alone" do
      assert rb_diffs(mailer("  def go(e), do: render_body(e, \"welcome.html\")")) ==
               [{~s|render_body(e, "welcome.html")|, "e"}]
    end

    test "a computed template gets the removal mutant alone" do
      assert rb_diffs(mailer("  def go(e, t), do: render_body(e, t, %{})")) ==
               [{"render_body(e, t, %{})", "e"}]
    end

    test "nil and boolean atoms are never treated as templates" do
      for value <- ["nil", "false"] do
        source =
          "defmodule M do\n  def go(e, a), do: Phoenix.Swoosh.render_body(e, #{value}, a)\nend\n"

        assert rb_diffs(source) == [{"Phoenix.Swoosh.render_body(e, #{value}, a)", "e"}]
      end
    end

    test "narrowing preserves the aliased written form" do
      source = """
      defmodule M do
        alias Phoenix.Swoosh, as: PS
        def go(e, a), do: PS.render_body(e, :welcome, a)
      end
      """

      assert {"PS.render_body(e, :welcome, a)", ~s|PS.render_body(e, "welcome.html", a)|} in rb_diffs(
               source
             )
    end
  end

  describe "the template position's registry :skip pin" do
    test "core's value families leave the template alone when this family is enabled" do
      source = mailer("  def go(e, n), do: render_body(e, :welcome, %{name: n})")
      mutators = [Mutare.Mutators.AtomLiteral, Mutare.Mutators.StringLiteral, RenderBody]

      refute Enum.any?(diffs(source, mutators, @ext), fn {_family, original, _mutated} ->
               original in [":welcome", "\"welcome.html\""]
             end)
    end

    test "the pin covers qualified sites too" do
      source =
        "defmodule M do\n  def go(e, a), do: Phoenix.Swoosh.render_body(e, \"welcome.html\", a)\nend\n"

      mutators = [Mutare.Mutators.StringLiteral, RenderBody]

      assert diffs(source, mutators) == [
               {:render_body, ~s|Phoenix.Swoosh.render_body(e, "welcome.html", a)|, "e"}
             ]
    end

    test "assigns values are still core's to mutate" do
      source = mailer("  def go(e), do: render_body(e, :welcome, %{greeting: \"hello\"})")

      strings =
        diffs_for(source, [Mutare.Mutators.StringLiteral, RenderBody], :string, @ext)

      assert {"\"hello\"", "\"\""} in strings
    end

    test "control: without this family the sentinel mutants do fire on the template" do
      source = mailer("  def go(e, a), do: Phoenix.Swoosh.render_body(e, :welcome, a)")

      assert {":welcome", ":mutare"} in diffs_for(
               source,
               [Mutare.Mutators.AtomLiteral],
               :atom,
               @ext
             )
    end
  end

  describe "scope" do
    test "a wrong-arity qualified call is left alone" do
      one = "defmodule M do\n  def go(e), do: Phoenix.Swoosh.render_body(e)\nend\n"

      four =
        "defmodule M do\n  def go(e, a), do: Phoenix.Swoosh.render_body(e, :welcome, a, :x)\nend\n"

      assert rb_diffs(one) == []
      assert rb_diffs(four) == []
    end

    test "does not touch a same-named local render_body (no use, no import)" do
      source = """
      defmodule M do
        def go(e), do: render_body(e, :welcome)
        def render_body(e, _template, _assigns \\\\ %{}), do: e
      end
      """

      assert rb_diffs(source) == []
    end

    test "leaves other Phoenix.Swoosh calls untouched" do
      source = "defmodule M do\n  def go(e), do: Phoenix.Swoosh.put_view(e, V)\nend\n"

      assert rb_diffs(source) == []
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      assert RenderBody.mutate(Mutare.AST.parse!("Phoenix.Swoosh.render_body(e, :welcome, a)")) ==
               :skip
    end
  end

  describe "variant labels (# mutare:ignore[render_body:<kind>])" do
    test "the declared vocabulary" do
      assert RenderBody.variants() == ["remove", "html_only", "text_only"]
    end

    test "a qualified directive suppresses one kind and leaves the others live" do
      source =
        mailer("  def go(e), do: render_body(e, :welcome) # mutare:ignore[render_body:text_only]")

      result =
        Mutare.transform_string(source,
          mutators: [RenderBody],
          extensions: [Mutare.Phoenix.Swoosh]
        )

      assert Enum.map(result.mutants, &{&1.variant, &1.ignored}) ==
               [{["remove"], false}, {["html_only"], false}, {["text_only"], true}]
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule RenderCompileDemo do
      use Phoenix.Swoosh, view: Sample.EmailView

      def welcome(email, name) do
        email
        |> render_body(:welcome, %{name: name})
      end

      def digest(email), do: render_body(email, "digest.html")

      def qualified(email, a), do: Phoenix.Swoosh.render_body(email, :notice, a)
    end
    """

    assert_metamutant_compiles(source, [RenderBody], @ext)
  end
end
