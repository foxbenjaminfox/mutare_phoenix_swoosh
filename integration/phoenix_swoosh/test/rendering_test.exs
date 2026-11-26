defmodule Mutare.Phoenix.Swoosh.Integration.MailView do
  use Phoenix.View, root: "test/templates", path: "mail"
end

defmodule Mutare.Phoenix.Swoosh.Integration.LayoutView do
  use Phoenix.View, root: "test/templates", path: "layout"
end

defmodule Mutare.Phoenix.Swoosh.Integration.RenderingTest do
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.Swoosh.{Layout, RenderBody}
  alias Mutare.Phoenix.Swoosh.Integration.{LayoutView, MailView}

  @extensions [extensions: [Mutare.Phoenix.Swoosh]]

  test "multipart narrowing renders just the selected real template" do
    source = """
    defmodule MultipartMailer do
      use Phoenix.Swoosh, view: #{inspect(MailView)}

      def welcome(email), do: email |> render_body(:welcome, name: "<Alex>")
    end
    """

    {[mailer], sites} = compile_metamutant(source, [RenderBody], @extensions)
    email = Swoosh.Email.new()
    baseline = mailer.welcome(email)

    assert baseline.html_body =~ "<p>Hello &lt;Alex&gt;</p>"
    assert baseline.text_body =~ "Hello <Alex>"

    html_only =
      with_active_mutant(variant_id(sites, "html_only"), fn -> mailer.welcome(email) end)

    assert html_only.html_body == baseline.html_body
    assert html_only.text_body == nil

    text_only =
      with_active_mutant(variant_id(sites, "text_only"), fn -> mailer.welcome(email) end)

    assert text_only.html_body == nil
    assert text_only.text_body == baseline.text_body
  end

  test "custom formats skip wrapper narrowings and make email narrowings raise" do
    source = """
    defmodule CustomMailer do
      use Phoenix.Swoosh, view: #{inspect(MailView)}, formats: %{"txt" => :text_body}

      def from_wrapper(email), do: render_body(email, :custom, name: "Alex")

      def from_email(email) do
        email
        |> put_view(#{inspect(MailView)})
        |> Phoenix.Swoosh.render_body(:custom, name: "Alex")
      end
    end
    """

    {[mailer], sites} = compile_metamutant(source, [RenderBody], @extensions)
    email = Swoosh.Email.new()
    from_wrapper = mailer.from_wrapper(email)
    assert from_wrapper.text_body =~ "Custom hello Alex"
    assert from_wrapper.html_body == nil

    assert Enum.map(sites, & &1.variant) == [["remove"], ["remove"], ["html_only"], ["text_only"]]

    email = Phoenix.Swoosh.put_new_formats(email, %{"txt" => :text_body})
    baseline = mailer.from_email(email)
    assert baseline.text_body == from_wrapper.text_body

    for variant <- ["html_only", "text_only"] do
      assert_raise RuntimeError, ~r/does not use the standard/, fn ->
        with_active_mutant(variant_id(sites, variant), fn -> mailer.from_email(email) end)
      end
    end
  end

  test "layout suppression overrides the winning keyword assign" do
    source = """
    defmodule BrandedMailer do
      use Phoenix.Swoosh, view: #{inspect(MailView)}

      def welcome(email, layout) do
        render_body(email, "welcome.text", name: "Alex", layout: false, layout: layout)
      end
    end
    """

    {[mailer], sites} = compile_metamutant(source, [Layout], @extensions)
    email = Swoosh.Email.new()
    layout = {LayoutView, :frame}
    assert mailer.welcome(email, layout).text_body =~ "Brand header"

    bare = with_active_mutant(variant_id(sites, "off"), fn -> mailer.welcome(email, layout) end)
    assert String.trim(bare.text_body) == "Hello Alex"
  end

  defp variant_id(sites, variant) do
    %{id: id} = Enum.find(sites, &(&1.variant == [variant]))
    id
  end
end
