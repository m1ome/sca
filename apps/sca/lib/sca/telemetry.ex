defmodule Sca.Telemetry do
  @moduledoc """
  Domain counters, for when there is no request id to grep for: logs answer
  "what happened to REQ-4711", these answer "how many signatures fail today".

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:sca, :request, :created]` | `count` | `type`, `tenant_id` |
  | `[:sca, :request, :decided]` | `count` | `status`, `type`, `tenant_id` |
  | `[:sca, :request, :refused]` | `count` | `reason`, `tenant_id` |
  | `[:sca, :request, :expired]` | `count` | `tenant_id` |
  | `[:sca, :binding, :bound]` | `count` | `tenant_id` |
  | `[:sca, :binding, :revoked]` | `count` | `reason`, `tenant_id` |
  | `[:sca, :webhook, :queued]` | `count` | `event`, `tenant_id` |
  | `[:sca, :webhook, :attempt]` | `duration_ms`, `attempt` | `event`, `status`, `tenant_id` |

  `tenant_id` is a tag, not a metric dimension: a time series per tenant per
  event is a cardinality problem at a thousand merchants.
  """

  import Telemetry.Metrics

  @doc "Fires a domain event. Measurements default to a plain counter."
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{count: 1}, metadata \\ %{}) do
    :telemetry.execute([:sca | event], measurements, metadata)
  end

  @doc """
  Metrics for the dashboards. Mounted by `ScaAdmin.Telemetry`.
  """
  def metrics do
    [
      counter("sca.request.created.count", tags: [:type]),
      counter("sca.request.decided.count", tags: [:status]),
      counter("sca.request.refused.count", tags: [:reason]),
      counter("sca.request.expired.count"),
      counter("sca.binding.bound.count"),
      counter("sca.binding.revoked.count", tags: [:reason]),
      counter("sca.webhook.queued.count", tags: [:event]),
      counter("sca.webhook.attempt.count", tags: [:status]),
      summary("sca.webhook.attempt.duration_ms", unit: :millisecond, tags: [:status])
    ]
  end
end
