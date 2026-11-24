## A channel of an activity as arrays, for storage.  The times: each the gap in seconds from the reading before (the first
## from the start, so 0), as unsigned LEB128 (`util/bytes/leb128`): a byte a reading, as long as the gaps are under two
## minutes, whether the device records every second or only when something changes ("smart recording": gaps of 2 to 10
## s).  The values: as the channel's packing says (kinds.nim).  Pure.

import std/[options, strformat]
import ../../core/errors
import ../fit/time
import ../util/bytes/leb128
import ./kinds

{.push raises: [].}

type Packed* = object ## What a row of `channel_series` holds.
  start*: UnixTime ## the time of the first reading
  count*: int
  gaps*, values*: string ## binary: `count` gaps and `count` values, as above

func pack*(ch: ChannelKind, rows: seq[(UnixTime, int64)]): Packed =
  ## (time, stored value) in time order, one per second at most, each value a reading of the channel (`readings`
  ## gives them).
  result.count = rows.len
  if rows.len == 0:
    return
  result.start = rows[0][0]
  var
    before = result.start
    previous = 0'i64
  for (t, v) in rows:
    doAssert t >= before, "readings are in time order"
    doAssert v in specs[ch].lowest .. specs[ch].highest, "a reading of its channel"
    result.gaps.putUleb uint64(int64(t) - int64(before))
    before = t
    case specs[ch].packing
    of pkU8:
      result.values.add char(v)
    of pkI8:
      result.values.add char(cast[uint8](int8(v)))
    of pkU16:
      result.values.add char(v and 0xFF)
      result.values.add char(v shr 8)
    of pkIncrement:
      result.values.putUleb zigzag(v - previous)
      previous = v

func unpack*(
    ch: ChannelKind, r: Packed
): seq[(UnixTime, int64)] {.raises: [StoreError].} =
  ## The readings back.  A StoreError if the arrays do not hold the count of readings the row says, exactly, each a
  ## reading of the channel.
  let name = specs[ch].name
  template broken() =
    raiseStore(
      fmt"the {name} arrays of an activity do not hold the readings their count says"
    )

  var
    t = int64(r.start)
    previous = 0'i64
    g = 0
    at = 0
  for i in 0 ..< r.count:
    let gap = getUleb(r.gaps, g)
    if gap.isNone or gap.get > uint64(high(int32)):
      broken()
    t += int64(gap.get)
    var v: int64
    case specs[ch].packing
    of pkU8:
      if at >= r.values.len:
        broken()
      v = int64(ord(r.values[at]))
      inc at
    of pkI8:
      if at >= r.values.len:
        broken()
      v = int64(cast[int8](r.values[at]))
      inc at
    of pkU16:
      if at + 1 >= r.values.len:
        broken()
      v = int64(ord(r.values[at])) or (int64(ord(r.values[at + 1])) shl 8)
      at += 2
    of pkIncrement:
      let change = getUleb(r.values, at)
      # (no change between two readings is larger than the channel's span, which `pack` cannot exceed; checked
      # before the addition, which could overflow)
      let span = uint64(specs[ch].highest - specs[ch].lowest)
      if change.isNone or change.get > 2 * span:
        broken()
      v = previous + unzigzag(change.get)
      previous = v
    if v notin specs[ch].lowest .. specs[ch].highest:
      broken()
    result.add (UnixTime(t), v)
  if g != r.gaps.len or at != r.values.len:
    broken()
