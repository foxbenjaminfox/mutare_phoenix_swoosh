defmodule Mutare.Phoenix.Swoosh.SemanticsTest do
  # Selecting a mutant is VM-global (see Mutare.Test), so these live-mutant checks are not
  # async. The fixtures compile against the test-support `Phoenix.Swoosh` stand-in, whose
  # `render_body` really routes each extension's render onto `html_body`/`text_body`.
  use ExUnit.Case, async: false

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.{Layout, RenderBody}

  test "an active removal mutant ships the email with no rendered body" do
    source = """
    defmodule RbMailer do
      use Phoenix.Swoosh, view: Sample.EmailView

      def welcome(email, name) do
        email
        |> render_body(:welcome, %{name: name})
      end
    end
    """

    {[mod], sites} =
      compile_metamutant(source, [RenderBody], extensions: [Mutare.Phoenix.Swoosh])

    baseline = mod.welcome(Swoosh.Email.new(), "Ann")
    assert baseline.html_body == "rendered welcome.html"
    assert baseline.text_body == "rendered welcome.text"
    assert baseline.assigns == %{name: "Ann"}

    id = site_id(sites, {~r/render_body/, "Elixir.Function.identity()"})
    removed = with_active_mutant(id, fn -> mod.welcome(Swoosh.Email.new(), "Ann") end)

    assert removed.html_body == nil
    assert removed.text_body == nil
  end

  test "an active narrowing mutant renders exactly one body part" do
    source = """
    defmodule NarrowMailer do
      use Phoenix.Swoosh, view: Sample.EmailView

      def welcome(email), do: render_body(email, :welcome)
    end
    """

    {[mod], sites} =
      compile_metamutant(source, [RenderBody], extensions: [Mutare.Phoenix.Swoosh])

    baseline = mod.welcome(Swoosh.Email.new())
    assert baseline.html_body == "rendered welcome.html"
    assert baseline.text_body == "rendered welcome.text"

    html_id = site_id(sites, {~r/render_body/, ~r/"welcome\.html"/})
    html_only = with_active_mutant(html_id, fn -> mod.welcome(Swoosh.Email.new()) end)
    assert html_only.html_body == "rendered welcome.html"
    assert html_only.text_body == nil

    text_id = site_id(sites, {~r/render_body/, ~r/"welcome\.text"/})
    text_only = with_active_mutant(text_id, fn -> mod.welcome(Swoosh.Email.new()) end)
    assert text_only.html_body == nil
    assert text_only.text_body == "rendered welcome.text"
  end

  test "an active layout-removal mutant leaves the layout where it was" do
    source = """
    defmodule LayoutMailer do
      use Phoenix.Swoosh, view: Sample.EmailView

      def branded(email), do: put_layout(email, {BrandLayout, :override})
    end
    """

    {[mod], sites} = compile_metamutant(source, [Layout])

    assert Phoenix.Swoosh.layout(mod.branded(Swoosh.Email.new())) == {BrandLayout, :override}

    id = site_id(sites, {~r/put_layout/, "email"})

    assert with_active_mutant(id, fn -> mod.branded(Swoosh.Email.new()) end)
           |> Phoenix.Swoosh.layout() == false
  end

  test "an active put_new-removal mutant leaves the layout unset" do
    source = """
    defmodule NewLayoutMailer do
      use Phoenix.Swoosh, view: Sample.EmailView

      def branded(email), do: put_new_layout(email, {BrandLayout, :email})
    end
    """

    {[mod], sites} = compile_metamutant(source, [Layout])

    assert Phoenix.Swoosh.layout(mod.branded(Swoosh.Email.new())) == {BrandLayout, :email}

    id = site_id(sites, {~r/put_new_layout/, "email"})

    assert with_active_mutant(id, fn -> mod.branded(Swoosh.Email.new()) end)
           |> Phoenix.Swoosh.layout() == false
  end
end
