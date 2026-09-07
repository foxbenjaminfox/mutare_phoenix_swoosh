defmodule Mutare.Phoenix.Swoosh.Routes do
  @moduledoc false

  # The call-routing declarations both families build on, in one place.
  #
  # `render_body/0` is declared by *both* families — `:render_body` mutates the call, and
  # `:mail_layout` reaches the layout through its assigns argument — so the route facts live
  # here rather than being written twice and drifting apart. Identical declarations from
  # several code providers coalesce in the registry; conflicting ones raise, which is exactly
  # why there is only one copy of each.

  @spec render_body() :: [Mutare.CallRouting.route()]
  def render_body do
    [
      {Phoenix.Swoosh, :render_body, 2, [:expression, :raw]},
      {Phoenix.Swoosh, :render_body, 3, [:expression, :raw, :expression]}
    ]
  end

  @spec layout_setters() :: [Mutare.CallRouting.route()]
  def layout_setters do
    [
      {Phoenix.Swoosh, :put_layout, 2, [:expression, :raw]},
      {Phoenix.Swoosh, :put_new_layout, 2, [:expression, :raw]}
    ]
  end

  @spec formats() :: [Mutare.CallRouting.route()]
  def formats, do: [{Phoenix.Swoosh, :put_new_formats, 2, [:expression, :raw]}]
end
