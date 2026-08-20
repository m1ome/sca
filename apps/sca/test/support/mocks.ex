# Compiled rather than defined in `test_helper.exs`, so the consoles and the API
# can set expectations on them too: a test helper only runs for its own app.
Mox.defmock(Sca.Webhooks.ClientMock, for: Sca.Webhooks.Client)
Mox.defmock(Sca.Push.ClientMock, for: Sca.Push.Client)
