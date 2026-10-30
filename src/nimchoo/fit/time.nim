## FIT time: seconds since 1989-12-31T00:00:00Z.

import std/times

const fitEpoch* = 631_065_600'i64  ## 1989-12-31T00:00:00Z as unix time

func fitToUnix*(t: int64): int64 {.raises: [].} = t + fitEpoch

func fitToTime*(t: int64): Time {.raises: [].} = fromUnix(t + fitEpoch)

func expandTimestamp16*(t16: uint16, current: int64):
    tuple[time: int64, backwards: bool] {.raises: [].} =
  ## Full timestamp from the low 16 bits, given the latest full timestamp
  ## (FIT seconds).  A small backwards jump is treated as time moving back
  ## (`backwards` is set); otherwise we wrap forwards.
  let delta = int64(t16) - (current and 0xffff)
  if delta < 0 and abs(delta) < 0x8000:
    (current + delta, true)
  else:
    (current + (delta and 0xffff), false)
