defmodule ScaUi do
  @moduledoc """
  The Enum8 design system, shared by both consoles.

  The client portal and the admin console are one system in the handoff
  package, so they are one module here: a primitive that drifts between them is
  a bug nobody notices until the screens stop looking related.

  Tailwind 4 utilities and Heroicons outline only. Tokens live in
  `assets/css/tokens.css` and are imported by each app's stylesheet.
  """
end
