defmodule Sca.Push.ClientTest do
  @moduledoc """
  Sending with nothing to send with. Not `async`: these rewrite app config.
  """

  use ExUnit.Case, async: false

  alias Sca.Push.Client.Fcm

  setup do
    previous = Application.get_env(:sca, Sca.Push)
    on_exit(fn -> Application.put_env(:sca, Sca.Push, previous) end)

    :ok
  end

  test "sending without credentials is a no-op, not a failure" do
    Application.put_env(:sca, Sca.Push, [])

    assert :ok = Fcm.send(%{"message" => %{}})
  end

  test "a dead Goth is a failed send, not a crash" do
    # Goth is `:temporary`: a broken key kills it and nothing brings it back.
    Application.put_env(:sca, Sca.Push, project_id: "sca-test", credentials: %{})

    assert {:error, "goth is unavailable:" <> _} = Fcm.send(%{"message" => %{}})
  end
end
