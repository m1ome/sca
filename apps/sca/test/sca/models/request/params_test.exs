defmodule Sca.Models.Request.ParamsTest do
  use ExUnit.Case, async: true

  alias Sca.Models.Request.Params

  describe "normalize/1" do
    test "trims and drops what the caller left empty" do
      assert Params.normalize(%{"beneficiary" => "  ACME Ltd  ", "note" => "   "}) ==
               %{"beneficiary" => "ACME Ltd"}
    end

    test "puts money into its canonical form" do
      assert Params.normalize(%{"amount" => "1 249,00"}) == %{"amount" => "1249.00"}
      assert Params.normalize(%{"amount" => "100.50"}) == %{"amount" => "100.50"}
      assert Params.normalize(%{"currency" => "eur"}) == %{"currency" => "EUR"}
    end

    test "leaves an unparseable amount alone, so the error names what was sent" do
      assert Params.normalize(%{"amount" => "a lot"}) == %{"amount" => "alot"}
    end

    test "renders scalars as text without rounding them" do
      assert Params.normalize(%{"count" => 3, "flag" => true}) ==
               %{"count" => "3", "flag" => "true"}
    end
  end

  describe "validate/2" do
    test "a complete payment passes" do
      params = %{"amount" => "100.50", "currency" => "EUR", "beneficiary" => "ACME Ltd"}

      assert Params.validate(:payment, params) == []
    end

    test "a payment needs amount, currency and beneficiary" do
      assert Params.validate(:payment, %{}) |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
               ~w(amount beneficiary currency)
    end

    test "a login needs an ip, and it has to be one" do
      assert [{"ip", _message}] = Params.validate(:login, %{})
      assert [{"ip", message}] = Params.validate(:login, %{"ip" => "999.1.1.1"})
      assert message =~ "not an IP"
      assert Params.validate(:login, %{"ip" => "2001:db8::1"}) == []
    end

    test "a freeform card requires nothing" do
      assert Params.validate(:freeform, %{}) == []
      assert Params.validate(:freeform, %{"anything" => "goes"}) == []
    end

    test "amount and currency formats are checked wherever they appear" do
      assert [{"amount", _message}] = Params.validate(:freeform, %{"amount" => "10.505"})
      assert [{"currency", _message}] = Params.validate(:freeform, %{"currency" => "EURO"})
    end

    test "nested values are refused: the device could not reproduce them" do
      assert [{"items", message}] = Params.validate(:freeform, %{"items" => %{"a" => 1}})
      assert message =~ "not signable"

      assert [{"items", _message}] = Params.validate(:freeform, %{"items" => ["a", "b"]})
    end

    test "a card stays small enough to read on a phone" do
      many = Map.new(1..(Params.max_params() + 1), &{"key#{&1}", "value"})
      assert [{"params", message}] = Params.validate(:freeform, many)
      assert message =~ "no more than"

      assert [{"note", message}] =
               Params.validate(:freeform, %{"note" => String.duplicate("x", 201)})

      assert message =~ "at most 200 characters"

      long_key = String.duplicate("k", 41)
      assert [{^long_key, message}] = Params.validate(:freeform, %{long_key => "value"})
      assert message =~ "field name"
    end

    test "extra params are allowed on every type" do
      params = %{
        "amount" => "10.00",
        "currency" => "EUR",
        "beneficiary" => "ACME Ltd",
        "order" => "A-17"
      }

      assert Params.validate(:payment, params) == []
    end
  end
end
