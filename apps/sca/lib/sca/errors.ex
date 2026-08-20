defmodule Sca.Errors do
  @moduledoc """
  One shape for errors leaving the domain.

  Actions answer `{:error, atom}` for a refusal the caller cannot fix by editing
  a field (`:not_yours`, `:already_decided`, `:invalid_signature`), and
  `{:error, %Ecto.Changeset{}}` when the input itself is wrong. This module
  turns the second kind into something an HTTP layer can render without knowing
  about Ecto.

      Errors.to_map(changeset)
      #=> %{"amount" => ["must be a number, e.g. 100.50"]}

  Card params are reported against the param the merchant sent — they live in a
  single `payload` column, but "payload amount is required" would be useless in
  a form.
  """

  @doc "Changeset errors as `%{field => [message]}`, keyed the way the caller sent them."
  @spec to_map(Ecto.Changeset.t()) :: %{String.t() => [String.t()]}
  def to_map(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} -> {message, opts} end)
    |> flatten()
  end

  defp flatten(errors, prefix \\ nil) do
    Enum.reduce(errors, %{}, fn {field, value}, acc ->
      Map.merge(acc, entry(field, value, prefix), fn _key, one, two -> one ++ two end)
    end)
  end

  defp entry(field, value, prefix) when is_map(value), do: flatten(value, key(field, prefix))

  defp entry(field, messages, prefix) when is_list(messages) do
    Enum.reduce(messages, %{}, fn {message, opts}, acc ->
      key = opts[:param] || key(field, prefix)

      Map.update(
        acc,
        to_string(key),
        [interpolate(message, opts)],
        &(&1 ++ [interpolate(message, opts)])
      )
    end)
  end

  defp key(field, nil), do: to_string(field)
  defp key(field, prefix), do: "#{prefix}.#{field}"

  # `validate_length` and friends leave placeholders like %{count} in the message.
  defp interpolate(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end
end
