import std/[times, unittest]
import nimchoo/fit/time

suite "time":
  test "fit epoch":
    check fitToUnix(0) == 631065600
    check fitToTime(0).utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'") ==
      "1989-12-31T00:00:00Z"
    check fitToTime(86400).utc.format("yyyy-MM-dd") == "1990-01-01"

  # the three cases from choochoo's Date16 docstring, scaled to 16 bits
  test "timestamp_16: simple increment":
    let r = expandTimestamp16(0x5e5e, 0x15c5c)
    check r.time == 0x15c5c + 0x202
    check not r.backwards
  test "timestamp_16: small decrement":
    let r = expandTimestamp16(0x5a5a, 0x15c5c)
    check r.time == 0x15c5c - 0x202
    check r.backwards
  test "timestamp_16: wrap-around":
    let r = expandTimestamp16(0x0010, 0x1fff0)
    check r.time == 0x20010
    check not r.backwards
