import std/[times, unittest]
import nimchoo/fit/time

suite "time":
  test "fit epoch":
    check fitToUnix(FitTime(0)) == UnixTime(631065600)
    check fitToTime(FitTime(0)).utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'") ==
      "1989-12-31T00:00:00Z"
    check fitToTime(FitTime(86400)).utc.format("yyyy-MM-dd") == "1990-01-01"

  test "what can be a FIT time: 32 bits, less the all-ones value that means no time":
    check isFitTime(FitTime(0)) and isFitTime(FitTime(0xFFFF_FFFE'i64))
    check not isFitTime(FitTime(-1)) and not isFitTime(FitTime(0xFFFF_FFFF'i64))
    check not isFitTime(FitTime(0x1_0000_0000'i64))
    check not isFitTime(FitTime(high(int64))) and not isFitTime(FitTime(low(int64)))

  # the three cases from choochoo's Date16 docstring, scaled to 16 bits
  test "timestamp_16: simple increment":
    let r = expandTimestamp16(0x5e5e, FitTime(0x15c5c))
    check r.time == FitTime(0x15c5c + 0x202)
    check not r.backwards
  test "timestamp_16: small decrement":
    let r = expandTimestamp16(0x5a5a, FitTime(0x15c5c))
    check r.time == FitTime(0x15c5c - 0x202)
    check r.backwards
  test "timestamp_16: wrap-around":
    let r = expandTimestamp16(0x0010, FitTime(0x1fff0))
    check r.time == FitTime(0x20010)
    check not r.backwards

  test "FIT seconds and Unix seconds are not mixed up":
    check not compiles(FitTime(1) < UnixTime(1))
    check not compiles(fitToUnix(UnixTime(1)))
    check not compiles(UnixTime(1) == FitTime(1))
    check not compiles(UnixTime(1) < 5) # (a plain number is not a time)
    check UnixTime(10) - UnixTime(4) == 6 # the difference is a number of seconds
    check FitTime(10) + 5 == FitTime(15)
