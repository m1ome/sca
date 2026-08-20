defmodule ScaUi.Format do
  @moduledoc """
  How a console prints a moment in time.

  Everything is stored in UTC, and a console is read by people in unknown
  places, so an absolute time always says `UTC` outright. Lists print the
  relative form — "2 hours ago" is what a person wants from a list — and carry
  the absolute one in a tooltip.
  """

  @minute 60
  @hour 3600
  @day 86_400

  @doc """
  Absolute, unambiguous, short.

      iex> ScaUi.Format.datetime(~U[2026-08-20 09:40:12.000000Z])
      "20 Aug 2026, 09:40 UTC"

      iex> ScaUi.Format.datetime(nil)
      "—"
  """
  @spec datetime(DateTime.t() | nil) :: String.t()
  def datetime(nil), do: "—"
  def datetime(at), do: Timex.format!(at, "{0D} {Mshort} {YYYY}, {h24}:{m} UTC")

  @doc """
  Date only.

      iex> ScaUi.Format.date(~U[2026-08-20 09:40:12.000000Z])
      "20 Aug 2026"
  """
  @spec date(DateTime.t() | nil) :: String.t()
  def date(nil), do: "—"
  def date(at), do: Timex.format!(at, "{0D} {Mshort} {YYYY}")

  @doc """
  How long ago, or how long from now: `2 hours ago`, `in 14 minutes`.

  Ours rather than Timex's `{relative}`, which reads "tomorrow" for two days
  away and rounds "in 3 hours" down to "in 2". A deadline shown short is worse
  than one shown plainly: past time is rounded down, time still to come is
  rounded up, so "in 14 minutes" lasts until 13 are left. Beyond a week the
  relative form stops meaning anything and the date itself is printed.
  """
  @spec relative(DateTime.t() | nil) :: String.t()
  def relative(nil), do: "—"

  def relative(at) do
    seconds = Timex.diff(at, Timex.now(), :second)
    # Zero is the same instant, and `Timex.diff/3` truncates towards it: a
    # moment half a second old must not read as one half a second away.
    direction = if seconds > 0, do: :future, else: :past

    case scale(abs(seconds), direction) do
      :now -> if direction == :past, do: "just now", else: "in less than a minute"
      :far -> date(at)
      {count, unit} -> phrase(count, unit, direction)
    end
  end

  defp scale(magnitude, _direction) when magnitude < @minute, do: :now

  defp scale(magnitude, direction) do
    cond do
      count(magnitude, @minute, direction) < 60 ->
        {count(magnitude, @minute, direction), "minute"}

      count(magnitude, @hour, direction) < 24 ->
        {count(magnitude, @hour, direction), "hour"}

      count(magnitude, @day, direction) < 7 ->
        {count(magnitude, @day, direction), "day"}

      true ->
        :far
    end
  end

  defp count(magnitude, unit, :past), do: div(magnitude, unit)
  defp count(magnitude, unit, :future), do: ceil(magnitude / unit)

  defp phrase(count, unit, direction) do
    unit = if count == 1, do: unit, else: unit <> "s"

    case direction do
      :past -> "#{count} #{unit} ago"
      :future -> "in #{count} #{unit}"
    end
  end
end
