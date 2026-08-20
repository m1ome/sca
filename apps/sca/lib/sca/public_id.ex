defmodule Sca.PublicId do
  @moduledoc """
  Reading and writing identifiers such as `TNT-1` or `BIN-42`.

  Postgres generates them (`Sca.Repo.Migration.add_public_id/2`); this is how
  the web layers accept one from a user.
  """

  @format ~r/\A(?<prefix>[A-Z][A-Z0-9]{0,7})-(?<number>\d+)\z/

  @doc """
  Prefix configured for a schema, or `nil` when it has none.

      iex> Sca.PublicId.prefix(Sca.Models.Tenant)
      "TNT"
  """
  def prefix(schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__public_id_prefix__, 0) do
      schema.__public_id_prefix__()
    end
  end

  @doc """
  Builds a public id.

      iex> Sca.PublicId.build("TNT", 42)
      "TNT-42"
  """
  def build(prefix, number) when is_binary(prefix) and is_integer(number) and number > 0 do
    "#{prefix}-#{number}"
  end

  @doc """
  Splits a public id into prefix and number.

      iex> Sca.PublicId.parse("TNT-42")
      {:ok, "TNT", 42}

      iex> Sca.PublicId.parse("nope")
      :error
  """
  def parse(public_id) when is_binary(public_id) do
    case Regex.named_captures(@format, public_id) do
      %{"prefix" => prefix, "number" => number} -> {:ok, prefix, String.to_integer(number)}
      nil -> :error
    end
  end

  def parse(_public_id), do: :error

  @doc """
  Whether the id belongs to the schema. Checked before the database, so a
  `BIN-1` in a tenant lookup is refused rather than silently missing.
  """
  def belongs_to?(public_id, schema) when is_atom(schema) do
    with expected when is_binary(expected) <- prefix(schema),
         {:ok, ^expected, _number} <- parse(public_id) do
      true
    else
      _other -> false
    end
  end
end
