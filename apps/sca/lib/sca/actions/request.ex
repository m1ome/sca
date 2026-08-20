defmodule Sca.Actions.Request do
  @moduledoc """
  Raising a card on a device and closing it: by the user, the merchant or the
  clock.

  Two rules carry the security of the feature. The hash is computed here from
  the params we store and recomputed on the phone from what it *displays*, so a
  card that says one thing and hashes another is refused (WYSIWYS, PSD2 RTS
  Art 5). A decision is accepted once, pending, unexpired and signed — which is
  what makes a replay harmless.
  """

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Actions.Binding, as: BindingActions
  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Push
  alias Sca.Repo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Telemetry
  alias Sca.Webhooks

  @decisions %{"confirm" => :confirmed, "deny" => :declined}

  @doc """
  Raises a request on a bound device.

  Params are normalised per type (`Sca.Models.Request.Params`); the hash, the
  challenge and the deadline (from tenant settings) are ours. A revoked device
  is refused: a card nobody can answer is worse than an error.
  """
  @spec create(Models.Binding.t(), map()) ::
          {:ok, Models.Request.t()} | {:error, :binding_not_active | Ecto.Changeset.t()}
  def create(%Models.Binding{} = binding, attrs) do
    if binding.status == :active do
      Repo.transact(fn -> raise_card(binding, attrs) end)
    else
      Logger.warning(
        "[actions.request.create] refused: #{binding.public_id} is #{binding.status}"
      )

      {:error, :binding_not_active}
    end
  end

  defp raise_card(binding, attrs) do
    with {:ok, request} <- RequestRepo.create(request_attrs(binding, attrs)),
         {:ok, _delivery} <- Webhooks.queue("request.created", request),
         # Best effort: a missed push still shows up on the next poll.
         {:ok, _push} <- Push.queue(request, binding) do
      Logger.info(
        "[actions.request.create] #{request.public_id} #{request.type} on #{binding.public_id}"
      )

      Telemetry.emit([:request, :created], %{count: 1}, %{
        type: request.type,
        tenant_id: request.tenant_id
      })

      {:ok, request}
    else
      {:error, error} ->
        Logger.warning(
          "[actions.request.create] rejected for #{binding.public_id}: #{reason(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Records the device's decision after verifying its signature.

  `decision` is the client's wire word. A signature that does not check out
  counts against the binding; five consecutive failures revoke it.
  """
  @spec decide(Models.Request.t(), Models.Binding.t(), String.t() | atom(), String.t()) ::
          {:ok, Models.Request.t()}
          | {:error,
             :invalid_decision
             | :not_found
             | :not_yours
             | :already_decided
             | :expired
             | :invalid_signature}
  def decide(%Models.Request{} = request, %Models.Binding{} = binding, decision, signature) do
    with {:ok, status} <- cast_decision(decision) do
      request
      |> decide_transaction(binding, status, signature)
      |> handle_decision(binding)
    end
  end

  @doc "Closes a pending request from our side, without asking the device."
  @spec cancel(Models.Request.t()) :: {:ok, Models.Request.t()} | {:error, :not_pending | term()}
  def cancel(%Models.Request{} = request) do
    if Models.Request.pending?(request) do
      Repo.transact(fn -> cancel_request(request) end)
    else
      {:error, :not_pending}
    end
  end

  defp cancel_request(request) do
    with {:ok, cancelled} <-
           RequestRepo.change(request, status: :cancelled, decided_at: Timex.now()),
         {:ok, _delivery} <- Webhooks.queue("request.cancelled", cancelled) do
      Logger.info("[actions.request.cancel] #{cancelled.public_id} cancelled")

      {:ok, cancelled}
    else
      {:error, error} ->
        Logger.warning("[actions.request.cancel] #{request.public_id} failed: #{reason(error)}")

        {:error, error}
    end
  end

  @doc """
  Closes every request past its deadline and tells the merchants.

  Runs once a minute from `Sca.Workers.RequestExpiryWorker`, and again whenever
  a device asks what it owes an answer to. Nothing depends on the job being on
  time; it only makes the webhook land at the deadline rather than at the next
  glance.
  """
  @spec expire_overdue() :: [Models.Request.t()]
  def expire_overdue do
    case Repo.transact(&close_overdue/0) do
      {:ok, expired} ->
        report_expired(expired)

        expired

      {:error, error} ->
        Logger.error("[actions.request.expire_overdue] failed: #{reason(error)}")

        []
    end
  end

  defp close_overdue do
    expired = RequestRepo.expire_overdue(Timex.now())

    Enum.reduce_while(expired, {:ok, expired}, fn request, acc ->
      case Webhooks.queue("request.expired", request) do
        {:ok, _queued} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp report_expired([]), do: :ok

  defp report_expired(expired) do
    Logger.info("[actions.request.expire_overdue] closed #{length(expired)} overdue request(s)")

    for request <- expired do
      Telemetry.emit([:request, :expired], %{count: 1}, %{tenant_id: request.tenant_id})
    end

    :ok
  end

  defp decide_transaction(request, binding, status, signature) do
    Repo.transact(fn ->
      with {:ok, locked} <- RequestRepo.lock(request.id),
           :ok <- ensure_owner(locked, binding),
           :ok <- ensure_pending(locked),
           :ok <- ensure_not_expired(locked),
           {:ok, message} <- verify(locked, binding, status, signature) do
        record(locked, binding, status, message, signature)
      end
    end)
  end

  defp ensure_owner(%Models.Request{binding_id: id}, %Models.Binding{id: id}), do: :ok
  defp ensure_owner(_request, _binding), do: {:error, :not_yours}

  defp ensure_pending(%Models.Request{status: :pending}), do: :ok
  defp ensure_pending(_request), do: {:error, :already_decided}

  defp ensure_not_expired(%Models.Request{} = request) do
    if Timex.before?(request.expires_at, Timex.now()) do
      {:error, {:expired, request}}
    else
      :ok
    end
  end

  defp verify(request, binding, status, signature) do
    message =
      Crypto.signing_string(request.id, request.nonce, wire(status), request.payload_hash)

    case Crypto.verify(binding.algorithm, binding.public_key, message, signature) do
      :ok -> {:ok, message}
      {:error, _reason} -> {:error, :invalid_signature}
    end
  end

  defp record(request, binding, status, message, signature) do
    with {:ok, decided} <-
           RequestRepo.record_decision(request, status, %{
             "signed_payload" => message,
             "signature" => signature,
             "signature_algorithm" => binding.algorithm || Crypto.algorithm_ecdsa_p256()
           }),
         {:ok, _binding} <- BindingRepo.change(binding, failed_attempts: 0),
         {:ok, _delivery} <- Webhooks.queue("request.#{decided.status}", decided) do
      Logger.info(
        "[actions.request.decide] #{decided.public_id} #{decided.status} by #{binding.public_id}"
      )

      Telemetry.emit([:request, :decided], %{count: 1}, %{
        status: decided.status,
        type: decided.type,
        tenant_id: decided.tenant_id
      })

      {:ok, decided}
    end
  end

  defp handle_decision({:ok, request}, _binding), do: {:ok, request}

  defp handle_decision({:error, error}, binding) do
    refusal = refusal(error)

    Logger.warning("[actions.request.decide] refused for #{binding.public_id}: #{refusal}")

    Telemetry.emit([:request, :refused], %{count: 1}, %{
      reason: refusal,
      tenant_id: binding.tenant_id
    })

    on_refusal(error, binding)

    {:error, refusal}
  end

  defp refusal({:expired, _request}), do: :expired
  defp refusal(error), do: error

  # Closed in passing, so the next poll agrees with the answer the device got.
  defp on_refusal({:expired, request}, _binding) do
    {:ok, _request} = RequestRepo.change(request, status: :expired)
  end

  defp on_refusal(:invalid_signature, binding), do: count_failed_attempt(binding)
  defp on_refusal(_error, _binding), do: :ok

  # PSD2 RTS Art 4(3)(b): five consecutive bad signatures retire the device.
  # Counted here because a signature is only ever judged here, and after the
  # decision rolled back — an attempt forgotten on failure is not a counter.
  defp count_failed_attempt(binding) do
    attempts = binding.failed_attempts + 1
    limit = Models.Binding.max_failed_attempts()

    Logger.warning(
      "[actions.request.decide] bad signature from #{binding.public_id} #{attempts}/#{limit}"
    )

    case BindingRepo.change(binding, failed_attempts: attempts) do
      {:ok, binding} ->
        if attempts >= limit, do: BindingActions.revoke(binding, :lockout), else: {:ok, binding}

      {:error, error} ->
        Logger.error("[actions.request.decide] cannot count the attempt: #{reason(error)}")

        {:error, error}
    end
  end

  defp request_attrs(binding, attrs) do
    attrs
    |> stringify()
    |> Map.put("tenant_id", binding.tenant_id)
    |> Map.put("binding_id", binding.id)
    |> Map.put_new_lazy("nonce", fn -> Crypto.random_token(16) end)
    |> Map.put_new_lazy("expires_at", fn -> default_expires_at(binding) end)
  end

  defp default_expires_at(binding) do
    %{tenant: tenant} = Repo.preload(binding, :tenant)

    Timex.shift(Timex.now(), seconds: tenant.settings.default_request_timeout_seconds)
  end

  # The client sends the wire word; our own callers may say the status outright.
  defp cast_decision(decision) when is_binary(decision) do
    case Map.fetch(@decisions, decision) do
      {:ok, status} -> {:ok, status}
      :error -> {:error, :invalid_decision}
    end
  end

  defp cast_decision(status) when status in [:confirmed, :declined], do: {:ok, status}
  defp cast_decision(_decision), do: {:error, :invalid_decision}

  # ...and the device signed the wire word, so the string has to come back.
  defp wire(:confirmed), do: "confirm"
  defp wire(:declined), do: "deny"
end
