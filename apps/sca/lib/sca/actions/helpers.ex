defmodule Sca.Actions.Helpers do
  @moduledoc """
  The small things every action does the same way.

      import Sca.Actions.Helpers
  """

  alias Sca.Errors

  @doc """
  String-keyed attrs.

  Actions merge what the caller sent with what they decide themselves
  (`tenant_id`, a generated nonce), and `Ecto.Changeset.cast/3` refuses a map
  that mixes atom and string keys — so everything is normalised on the way in.
  """
  @spec stringify(map() | keyword()) :: %{String.t() => term()}
  def stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  @doc """
  Whatever an action failed with, as one short string for a log line.

  A changeset is rendered the same way `Sca.Errors.to_map/1` renders it for an
  HTTP response — a log and a response should not disagree about why something
  was refused. Everything else is a domain reason (`:not_yours`, `:expired`, a
  transport error) and is simply inspected.
  """
  @spec reason(term()) :: String.t()
  def reason(%Ecto.Changeset{} = changeset), do: inspect(Errors.to_map(changeset))
  def reason(other), do: inspect(other)
end
