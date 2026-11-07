## FIT time: seconds since 1989-12-31T00:00:00Z.

import std/times

{.push raises: [].}

const fitEpoch* = 631_065_600'i64 ## 1989-12-31T00:00:00Z as unix time

type
  FitTime* = distinct int64
    ## seconds since 1989-12-31T00:00:00Z, as a FIT file counts them
  UnixTime* = distinct int64
    ## seconds since 1970-01-01T00:00:00Z, as the database holds them
  # (two kinds of seconds that differ by 631,065,600: the compiler must not let one be used as the other)

func `==`*(a, b: FitTime): bool {.borrow.}
func `<`*(a, b: FitTime): bool {.borrow.}
func `<=`*(a, b: FitTime): bool {.borrow.}
func `$`*(t: FitTime): string {.borrow.}
func `-`*(a, b: FitTime): int64 {.borrow.} ## seconds between
func `+`*(a: FitTime, secs: int64): FitTime {.borrow.}

func max*(a, b: FitTime): FitTime =
  (if a < b: b else: a)

func `==`*(a, b: UnixTime): bool {.borrow.}
func `<`*(a, b: UnixTime): bool {.borrow.}
func `<=`*(a, b: UnixTime): bool {.borrow.}
func `$`*(t: UnixTime): string {.borrow.}
func `-`*(a, b: UnixTime): int64 {.borrow.} ## seconds between
func `+`*(a: UnixTime, secs: int64): UnixTime {.borrow.}
func `-`*(a: UnixTime, secs: int64): UnixTime {.borrow.}
func cmp*(a, b: UnixTime): int =
  cmp(int64(a), int64(b))
func max*(a, b: UnixTime): UnixTime =
  (if a < b: b else: a)
func min*(a, b: UnixTime): UnixTime =
  (if a < b: a else: b)

func toTime*(t: UnixTime): Time {.raises: [].} =
  fromUnix(int64(t))

func fitToUnix*(t: FitTime): UnixTime {.raises: [].} =
  UnixTime(int64(t) + fitEpoch)

func fitToTime*(t: FitTime): Time {.raises: [].} =
  fromUnix(int64(t) + fitEpoch)

func expandTimestamp16*(
    t16: uint16, current: FitTime
): tuple[time: FitTime, backwards: bool] {.raises: [].} =
  ## Full timestamp from the low 16 bits, given the latest full timestamp
  ## (FIT seconds).  A small backwards jump is treated as time moving back
  ## (`backwards` is set); otherwise we wrap forwards.
  let delta = int64(t16) - (int64(current) and 0xffff)
  if delta < 0 and abs(delta) < 0x8000:
    (current + delta, true)
  else:
    (current + (delta and 0xffff), false)
