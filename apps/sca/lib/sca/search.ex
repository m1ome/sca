defmodule Sca.Search do
  @moduledoc """
  The one search box a list gets: paste an identifier, find the row.

  People arrive at a console holding an id out of a log, a webhook or an API
  response — a uuid — or out of another screen, where ids read `BIN-42`. Both
  are exact: this is a lookup, not a text search, and answering "no such thing"
  beats answering with something that merely looks similar.
  """

  @doc """
  A Flop filter for whatever the box holds, or `nil` when it holds nothing we
  can look up.

      iex> Sca.Search.filter("BIN-42")
      %{"field" => "public_id", "op" => "==", "value" => "BIN-42"}

      iex> Sca.Search.filter("not an id")
      nil
  """
  @spec filter(String.t() | nil) :: map() | nil
  def filter(term) when is_binary(term) do
    term = String.trim(term)

    cond do
      uuid?(term) -> %{"field" => "id", "op" => "==", "value" => String.downcase(term)}
      public_id?(term) -> %{"field" => "public_id", "op" => "==", "value" => String.upcase(term)}
      true -> nil
    end
  end

  def filter(_term), do: nil

  # The written form only. `Ecto.UUID.cast/1` also takes raw 16-byte binaries,
  # which quietly turns anything 16 characters long — "dana@example.com" — into
  # a lookup for a uuid nobody has.
  defp uuid?(term) do
    byte_size(term) == 36 and match?({:ok, _uuid}, Ecto.UUID.cast(term))
  end

  defp public_id?(term), do: Regex.match?(~r/\A[A-Za-z][A-Za-z0-9]{0,7}-\d+\z/, term)
end
