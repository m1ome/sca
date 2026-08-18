defmodule Sca.PublicIdTest do
  use ExUnit.Case, async: true

  doctest Sca.PublicId

  defmodule Probe do
    use Sca.Schema, public_id: "PRB"

    schema "public_id_probes" do
      public_id_field()
      timestamps()
    end
  end

  defmodule Plain do
    use Sca.Schema

    schema "plain" do
      timestamps()
    end
  end

  describe "prefix/1" do
    test "comes from the schema" do
      assert Sca.PublicId.prefix(Probe) == "PRB"
    end

    test "is nil for schemas without a public id" do
      assert Sca.PublicId.prefix(Plain) == nil
      assert Sca.PublicId.prefix(NotAModule) == nil
    end
  end

  describe "parse/1" do
    test "splits prefix and number" do
      assert Sca.PublicId.parse("TN-42") == {:ok, "TN", 42}
      assert Sca.PublicId.parse("CON-1") == {:ok, "CON", 1}
    end

    test "rejects anything else" do
      for input <- ["TN", "tn-1", "TN-", "TN-1x", "-1", "TN-1-2", "", nil] do
        assert Sca.PublicId.parse(input) == :error
      end
    end
  end

  test "build/2 round-trips through parse/1" do
    id = Sca.PublicId.build("TN", 7)

    assert id == "TN-7"
    assert Sca.PublicId.parse(id) == {:ok, "TN", 7}
  end

  describe "belongs_to?/2" do
    test "matches the schema prefix" do
      assert Sca.PublicId.belongs_to?("PRB-9", Probe)
      refute Sca.PublicId.belongs_to?("TN-9", Probe)
      refute Sca.PublicId.belongs_to?("garbage", Probe)
      refute Sca.PublicId.belongs_to?("PRB-9", Plain)
    end
  end

  test "schemas built on Sca.Schema use uuid keys and usec timestamps" do
    assert Probe.__schema__(:primary_key) == [:id]
    assert Probe.__schema__(:type, :id) == :binary_id
    assert Probe.__schema__(:type, :inserted_at) == :utc_datetime_usec
    assert :public_id in Probe.__schema__(:read_after_writes)
  end
end
