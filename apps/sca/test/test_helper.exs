Mox.defmock(Sca.Webhooks.ClientMock, for: Sca.Webhooks.Client)
Mox.defmock(Sca.Push.ClientMock, for: Sca.Push.Client)

ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Sca.Repo, :manual)
