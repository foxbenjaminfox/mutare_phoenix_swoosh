defmodule Mutare.Phoenix.Swoosh.LayoutConfigured do
  @moduledoc """
  A marker `Mutare.Phoenix.Swoosh` injects for a mailer whose `use Phoenix.Swoosh` line
  configures a layout (`layout: {LayoutView, :email}`).

  It is **not a behaviour anyone implements**. Mutare's `use` expansion records the behaviours a
  `use` injects and passes them to mutators as `context.behaviours`; this package's extension
  adds this module to that set to indicate a configured layout to `Mutare.Phoenix.Swoosh.Layout`.
  Nothing else reads it: the marker never reaches the metamutant source, the compiled program,
  or the report.

  This uses Mutare's module-scoped behaviour set, with two consequences:
  the marker does not apply to a *nested* module's calls (behaviours never inherit
  inwards), and a run with `--no-expand-uses` drops the injected half altogether. In both cases
  `off` is generated only when the call contains an author-written truthy `layout:` assign.

  It exists because the `use` line itself is unreachable — `use` options are compile-time
  configuration, pruned whole before any mutation could be delivered (see the "What's
  deliberately out of scope" section of the README). The marker records that configuration
  for use when mutating runtime calls. Without a layout in effect, suppressing one would
  produce an equivalent mutant.
  """
end
