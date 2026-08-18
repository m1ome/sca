defmodule Sca.Factory do
  @moduledoc """
  ExMachina factories for the domain.

  Factories live here rather than next to each schema so tests in every app
  have one place to look. Add one `def *_factory` per schema as the domain
  grows.
  """

  use ExMachina.Ecto, repo: Sca.Repo
end
