defmodule Sca.SearchTest do
  use ExUnit.Case, async: true

  doctest Sca.Search

  alias Sca.Search

  test "a uuid is looked up by id" do
    uuid = Ecto.UUID.generate()

    assert Search.filter(uuid) == %{"field" => "id", "op" => "==", "value" => uuid}
  end

  test "a readable id is looked up by public_id, however it was typed" do
    assert Search.filter("bin-42") == %{"field" => "public_id", "op" => "==", "value" => "BIN-42"}

    assert Search.filter("  TNT-1 ") == %{
             "field" => "public_id",
             "op" => "==",
             "value" => "TNT-1"
           }
  end

  test "anything else is not an id, so it is not a filter" do
    assert Search.filter("dana@example.com") == nil
    assert Search.filter("") == nil
    assert Search.filter(nil) == nil
  end
end
