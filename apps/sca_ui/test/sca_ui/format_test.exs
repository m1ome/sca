defmodule ScaUi.FormatTest do
  use ExUnit.Case, async: true

  doctest ScaUi.Format

  alias ScaUi.Format

  defp ago(shift), do: Format.relative(Timex.shift(Timex.now(), shift))

  test "an absolute time always names its zone" do
    assert Format.datetime(~U[2026-01-05 07:03:00.000000Z]) == "05 Jan 2026, 07:03 UTC"
  end

  test "past time is rounded down, the way people say it" do
    assert ago(minutes: -5) == "5 minutes ago"
    assert ago(minutes: -90) == "1 hour ago"
    assert ago(hours: -5) == "5 hours ago"
    assert ago(hours: -26) == "1 day ago"
    assert ago(days: -3) == "3 days ago"
  end

  test "time still to come is rounded up, so a deadline never reads short" do
    assert ago(minutes: 14) == "in 14 minutes"
    assert ago(hours: 3) == "in 3 hours"
    assert ago(days: 2) == "in 2 days"
  end

  test "seconds either way get their own words" do
    assert ago(seconds: -5) == "just now"
    assert ago(seconds: 45) == "in less than a minute"
  end

  test "something that just happened is not something about to happen" do
    assert Format.relative(Timex.now()) == "just now"
  end

  test "past a week the date itself says more" do
    assert ago(days: -40) =~ ~r/\A\d{2} \w{3} \d{4}\z/
    assert ago(days: 30) =~ ~r/\A\d{2} \w{3} \d{4}\z/
  end

  test "nothing to show is a dash, not a crash" do
    assert Format.datetime(nil) == "—"
    assert Format.date(nil) == "—"
    assert Format.relative(nil) == "—"
  end
end
