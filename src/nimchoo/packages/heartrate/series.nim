## The heart rate of an activity as arrays, for storage: one blob of time offsets (int32, seconds from the first reading) and one
## of beats per minute (uint8).  5 bytes a reading.  Pure.

import ../../core/errors
import ../fit/time
import ../importer/series

{.push raises: [].}

type Readings* = object
  t0*: UnixTime
  count*: int
  t*, bpm*: string ## binary: `count` entries of 4 and 1 bytes

func encodeReadings*(rows: seq[(UnixTime, int)]): Readings =
  ## (time, bpm) in time order, one per second at most; bpm from 1 to 255 (what `readings` gives).
  result.count = rows.len
  if rows.len == 0:
    return
  result.t0 = rows[0][0]
  result.t = newString(4 * rows.len)
  result.bpm = newString(rows.len)
  for i, (t, bpm) in rows:
    doAssert t >= result.t0 and int64(t) - int64(result.t0) <= int64(high(int32)),
      "readings are in time order, within 68 years"
    doAssert bpm in 1 .. 255, "a heart rate fits a byte"
    put32(result.t, 4 * i, int32(int64(t) - int64(result.t0)))
    result.bpm[i] = char(bpm)

func decodeReadings*(r: Readings): seq[(UnixTime, int)] {.raises: [StoreError].} =
  ## The readings back.  A StoreError if the arrays are not the lengths the count says.
  if r.t.len != 4 * r.count or r.bpm.len != r.count:
    raiseStore(
      "the heart-rate arrays of an activity are not the length their count says"
    )
  for i in 0 ..< r.count:
    result.add (UnixTime(int64(r.t0) + int64(get32(r.t, 4 * i))), ord(r.bpm[i]))
