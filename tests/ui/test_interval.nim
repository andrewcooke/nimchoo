import std/unittest
import nimchoo/packages/ui/interval

suite "interval: the one rule":
  test "under a minute: seconds":
    check interval(0.0) == "0s"
    check interval(2.1) == "2s"
    check interval(45.0) == "45s"
    check interval(59.4) == "59s"
  test "under an hour: minutes and two-digit seconds":
    check interval(60.0) == "1m00s"
    check interval(1325.0) == "22m05s"
    check interval(1320.0) == "22m00s"
    check interval(3599.0) == "59m59s"
  test "from an hour: hours and two-digit minutes, to the minute":
    check interval(3600.0) == "1h00m"
    check interval(16860.0) == "4h41m"
    check interval(16889.0) == "4h41m" # (29 s: the seconds are not shown)
    check interval(16891.0) == "4h42m" # (31 s: rounded up)
    check interval(86399.0) == "1d00h00m" # (rounded to the minute, which carries)
  test "from a day: days, two-digit hours and minutes":
    check interval(86400.0) == "1d00h00m"
    check interval(2 * 86400.0 + 3 * 3600.0 + 7 * 60.0) == "2d03h07m"
    check interval(353520.0) == "4d02h12m"
    check interval(12 * 86400.0 + 34 * 3600.0 + 56 * 60.0) == "13d10h56m"
  test "rounding carries into the next unit":
    check interval(59.6) == "1m00s"
    check interval(3599.7) == "1h00m"
    check interval(3600.0 + 29.0) == "1h00m"
    check interval(3600.0 + 31.0) == "1h01m"
    check interval(86399.7) == "1d00h00m"
  test "not a time: zero":
    check interval(-5.0) == "0s"
    check interval(0.0 / 0.0) == "0s"
