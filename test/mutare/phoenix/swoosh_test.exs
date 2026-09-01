defmodule Mutare.Phoenix.SwooshTest do
  @moduledoc """
  The package front: the `all/0` preset, the `Mutare.UseExpansion` override that surfaces
  `use Phoenix.Swoosh`'s hidden `render_body`, the in-process-expansion verdict it exists to
  correct, and composition with the `mutare_swoosh` base families.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.{Layout, RenderBody}
  alias Mutare.UseExpansion.Expansion

  doctest Mutare.Phoenix.Swoosh

  test "all/0 returns this package's two families, in order" do
    assert Mutare.Phoenix.Swoosh.all() == [RenderBody, Layout]
  end

  describe "the use-expansion override" do
    test "surfaces the whole import pair for the classic view: style" do
      args = [quote(do: [view: Sample.EmailView])]

      assert %Expansion{directives: directives, behaviours: []} =
               Mutare.Phoenix.Swoosh.expand_use(Phoenix.Swoosh, args, context())

      assert Enum.map(directives, &Macro.to_string/1) ==
               ["import Swoosh.Email", "import Phoenix.Swoosh"]
    end

    test "adds import Phoenix.View for the standalone template_root: style" do
      args = [quote(do: [template_root: "./templates"])]

      assert %Expansion{directives: directives} =
               Mutare.Phoenix.Swoosh.expand_use(Phoenix.Swoosh, args, context())

      assert Enum.map(directives, &Macro.to_string/1) ==
               ["import Swoosh.Email", "import Phoenix.Swoosh", "import Phoenix.View"]
    end

    test "declines every other use target" do
      assert Mutare.Phoenix.Swoosh.expand_use(Phoenix.LiveView, [], context()) == :decline
    end

    # `use Phoenix.Swoosh, opts` — the opts computed rather than written as a literal keyword
    # list. Nothing to inspect for `template_root:`, so only the base pair is surfaced.
    test "computed use options fall back to the base import pair (no Phoenix.View)" do
      args = [quote(do: mailer_opts())]

      assert %Expansion{directives: directives} =
               Mutare.Phoenix.Swoosh.expand_use(Phoenix.Swoosh, args, context())

      assert Enum.map(directives, &Macro.to_string/1) ==
               ["import Swoosh.Email", "import Phoenix.Swoosh"]
    end

    defp context, do: %{module: Sample.UserEmail, opts: []}
  end

  # The reason the override exists, pinned as behaviour: Mutare's in-process expansion of
  # `use Phoenix.Swoosh` *works* — it harvests the injected imports faithfully — but the
  # faithful harvest is `import Phoenix.Swoosh, except: [render_body: 3]` (the real `__using__`
  # provides `render_body` as a local def instead). So without the extension, bare calls to
  # every *other* Phoenix.Swoosh function resolve, while bare `render_body` stays invisible.
  describe "the in-process expansion verdict (no extension listed)" do
    test "bare put_layout resolves off the genuine harvested import" do
      assert diffs_for(mailer_source(), [Layout], :mail_layout) ==
               [{~s|put_layout(email, {LayoutV, "email.html"})|, "email"}]
    end

    test "bare render_body stays unresolved, so the family only fires qualified" do
      assert diffs_for(mailer_source(), [RenderBody], :render_body) ==
               [{"Phoenix.Swoosh.render_body(email, \"welcome.text\", %{})", "email"}]
    end
  end

  describe "with the extension listed" do
    test "the standalone template_root style resolves its bare render_body too" do
      source = """
      defmodule Standalone.UserEmail do
        use Phoenix.Swoosh, template_root: "./templates"

        def welcome(email, name) do
          render_body(email, :welcome, %{name: name})
        end
      end
      """

      diffs =
        diffs_for(source, [RenderBody], :render_body, extensions: [Mutare.Phoenix.Swoosh])

      assert {"render_body(email, :welcome, %{name: name})", "email"} in diffs
    end

    test "the bare render_body sites fire too" do
      diffs =
        diffs_for(mailer_source(), [RenderBody], :render_body,
          extensions: [Mutare.Phoenix.Swoosh]
        )

      assert {"render_body(email, :welcome, %{name: name})", "email"} in diffs
      assert {"Phoenix.Swoosh.render_body(email, \"welcome.text\", %{})", "email"} in diffs
    end
  end

  test "composes with the mutare_swoosh base families on one mailer" do
    source = """
    defmodule ComposedMailer do
      use Phoenix.Swoosh, view: Sample.EmailView

      def welcome(user) do
        new()
        |> subject("Hello")
        |> render_body(:welcome, %{name: user.name})
      end
    end
    """

    mutators =
      diffs(source, [Mutare.Swoosh.Subject, RenderBody], extensions: [Mutare.Phoenix.Swoosh])
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    assert :swoosh_subject in mutators
    assert :render_body in mutators
  end

  defp mailer_source do
    """
    defmodule Sample.UserEmail do
      use Phoenix.Swoosh, view: Sample.EmailView

      def welcome(email, name) do
        render_body(email, :welcome, %{name: name})
      end

      def branded(email) do
        put_layout(email, {LayoutV, "email.html"})
      end

      def text(email) do
        Phoenix.Swoosh.render_body(email, "welcome.text", %{})
      end
    end
    """
  end
end
