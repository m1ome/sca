defmodule Sca.Models.Request.Params do
  @moduledoc """
  The card fields a merchant sends with a request, and the rules they have to
  satisfy.

  Params are flat and scalar because they become `key=value` lines in the signed
  string (`Sca.Crypto.canonical_payload/1`), which the phone reproduces byte for
  byte. A nested object has no rendering the client could reproduce, so it is
  refused here instead of becoming a card the device declines to sign.

  Unknown keys are allowed and shown as extra rows: a merchant can add a field
  without a backend change, and the user still sees what the signature covers.
  """

  @required %{
    payment: ~w(amount currency beneficiary),
    login: ~w(ip),
    freeform: []
  }

  # Keeps a card readable on a phone, and bounds what one request can store.
  @max_params 20
  @max_key_length 40
  @max_value_length 200

  # Plain decimal, two fraction digits: exponent notation would be shown
  # verbatim on the phone.
  @max_amount_digits 15
  @max_amount_scale 2

  @doc "Params a given request type cannot go without."
  def required(type), do: Map.get(@required, type, [])

  @doc "Largest number of params a card may carry."
  def max_params, do: @max_params

  @doc """
  Trims, drops the blanks, canonicalises what we know: upper-case currency,
  dot-decimal amount. An untouched form field is an absent param, not an empty
  one.
  """
  def normalize(params) when is_map(params) do
    params
    |> Enum.map(fn {key, value} -> {String.trim(to_string(key)), normalize_value(key, value)} end)
    |> Enum.reject(fn {key, value} -> key == "" or value == "" end)
    |> Map.new()
  end

  def normalize(_params), do: %{}

  @doc """
  Every problem at once as `{key, message}` pairs, so a form can highlight them
  in one round trip. An empty list means the card is sound.
  """
  def validate(type, params) when is_map(params) do
    Enum.concat([
      missing(type, params),
      formats(params),
      shape(params)
    ])
  end

  defp missing(type, params) do
    for key <- required(type), blank?(Map.get(params, key)) do
      {key, "is required for a #{type} request"}
    end
  end

  defp formats(params) do
    Enum.flat_map(params, fn {key, value} ->
      case {key, value} do
        {"amount", amount} when is_binary(amount) ->
          check(amount?(amount), key, "must be a number, e.g. 100.50")

        {"currency", currency} when is_binary(currency) ->
          check(Money.Currency.exists?(currency), key, "must be an ISO 4217 code, e.g. EUR")

        {"ip", ip} when is_binary(ip) ->
          check(
            match?({:ok, _address}, :inet.parse_address(to_charlist(ip))),
            key,
            "is not an IP"
          )

        _other ->
          []
      end
    end)
  end

  defp shape(params) do
    too_many =
      check(map_size(params) <= @max_params, "params", "no more than #{@max_params} fields")

    per_param =
      Enum.flat_map(params, fn {key, value} ->
        cond do
          not is_binary(value) ->
            [{key, "must be a string, number or boolean — nested values are not signable"}]

          String.length(key) > @max_key_length ->
            [{key, "field name must be at most #{@max_key_length} characters"}]

          String.length(value) > @max_value_length ->
            [{key, "must be at most #{@max_value_length} characters"}]

          true ->
            []
        end
      end)

    too_many ++ per_param
  end

  defp check(true, _key, _message), do: []
  defp check(false, key, message), do: [{key, message}]

  # Parsed with Decimal, stored as the string it came in as: the phone hashes
  # the wire form, so it has to survive untouched.
  defp amount?(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> plain_positive_decimal?(decimal)
      _other -> false
    end
  end

  # Finite and non-negative only: `Decimal.parse/1` also takes "Inf" and "NaN",
  # which are nonsense on a payment card.
  defp plain_positive_decimal?(%Decimal{sign: 1, coef: coef, exp: exp})
       when is_integer(coef) and is_integer(exp) do
    scale = -exp

    scale >= 0 and scale <= @max_amount_scale and
      length(Integer.digits(coef)) <= @max_amount_digits
  end

  defp plain_positive_decimal?(_decimal), do: false

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  # Scalars are kept in the literal form they were sent in: "100.50" must not
  # round-trip through a float, or the hash the device recomputes stops matching.
  defp normalize_value(key, value) when is_binary(value) do
    value = String.trim(value)

    case to_string(key) do
      "currency" -> String.upcase(value)
      "amount" -> normalize_amount(value)
      _other -> value
    end
  end

  defp normalize_value(_key, value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_value(_key, value) when is_float(value), do: Float.to_string(value)
  defp normalize_value(_key, value) when is_boolean(value), do: to_string(value)
  defp normalize_value(_key, nil), do: ""
  # Left as it is, so `validate/2` reports it against the key that was sent.
  defp normalize_value(_key, value), do: value

  # "1 249,00" becomes "1249.00"; anything unparseable is returned untouched
  # so the error names what was typed.
  defp normalize_amount(value) do
    stripped = String.replace(value, [" ", " ", " "], "")

    if String.contains?(stripped, ",") and not String.contains?(stripped, ".") and
         length(String.split(stripped, ",")) == 2 do
      String.replace(stripped, ",", ".")
    else
      stripped
    end
  end
end
