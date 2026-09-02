defmodule Mutare.Phoenix.Swoosh.LayoutConfigured do
  @moduledoc """
  A marker `Mutare.Phoenix.Swoosh` injects for a mailer whose `use Phoenix.Swoosh` line
  configures a layout (`layout: {LayoutView, :email}`).

  It is **not a behaviour anyone implements**. Mutare's `use` expansion records the behaviours a
  `use` injects and hands them to mutators as `context.behaviours`; this package's extension
  puts this module in that set so `Mutare.Phoenix.Swoosh.Layout` can tell a mailer that renders
  *inside a layout* from one that renders bare. Nothing else reads it: the marker never reaches
  the metamutant source, the compiled program, or the report.

  Two consequences of riding that channel, both inherited from how Mutare scopes a module's
  behaviour set: the marker does not reach a *nested* module's calls (behaviours never inherit
  inwards), and a run with `--no-expand-uses` drops the injected half altogether. In both cases
  `off` falls back to its other trigger — an author-written truthy `layout:` assign — and mints
  nothing where it cannot tell.

  It exists because the `use` line itself is unreachable — `use` options are compile-time
  configuration, pruned whole before any mutation could be delivered (see the "What's
  deliberately out of scope" section of the README). The marker is how a compile-time *fact*
  crosses into the runtime call the family can actually mutate: without a layout in effect,
  suppressing one is an equivalent mutant, and this package does not mint those.
  """
end
