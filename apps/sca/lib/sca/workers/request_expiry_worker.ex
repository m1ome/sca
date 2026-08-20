defmodule Sca.Workers.RequestExpiryWorker do
  @moduledoc """
  Closes requests whose deadline has passed, once a minute.

  Expiry is also enforced on read and on decide, so nothing depends on this job
  being on time — what it adds is the `request.expired` webhook landing when the
  deadline passes rather than when someone next looks.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Sca.Actions.Request, as: RequestActions

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expired = RequestActions.expire_overdue()

    {:ok, length(expired)}
  end
end
