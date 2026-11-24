## The channels: the fields of a FIT `record` kept for each activity, one list from which the import step, the storage and
## the readers are all made.  A channel says its name (in the table `channel_series`), the record fields it is read from (the
## first that a record has wins: `enhanced_speed` before `speed`), its unit, how a value is stored (a whole number of steps
## of a size: the speed in mm/s, as FIT has it; packed as a byte or two, or as the change from the one before) and which
## stored values are readings at all (the rest are dropped when they are imported, with a warning).  Pure.

import std/options

{.push raises: [].}

type
  ChannelKind* = enum ## A field of the records that is kept.
    chHeartRate
    chCadence
    chTemperature
    chPower
    chSpeed
    chDistance

  Packing* = enum ## How the values are stored.
    pkU8 ## each an unsigned byte
    pkI8 ## each a signed byte
    pkU16 ## each two bytes, unsigned, little-endian
    pkIncrement
      ## each the change from the one before (the first from 0), zigzagged and in LEB128: a cumulative value that grows
      ## by a little a reading (the distance: about 2 bytes a reading, where 4 would hold the total)

  ChannelSpec* = object
    name*: string ## in the table and in messages: "heart_rate"
    title*: string ## what a person reads: "heart rate"
    fields*: seq[string] ## the record fields, the first a record has wins
    unit*: string ## of a value: "bpm"
    packing*: Packing
    step*: float ## what one stored unit is, in `unit` (0.001 for the speed: mm/s)
    lowest*, highest*: int64
      ## the stored values that are readings; the others are dropped

const specs*: array[ChannelKind, ChannelSpec] = [
  chHeartRate: ChannelSpec(
    # the field is a byte, whose 255 is FIT's "invalid" (the decoder drops it: a strap that has lost contact writes it);
    # zero is not a heart rate either: nothing known gives it a meaning, and none of the author's readings is zero
    name: "heart_rate",
    title: "heart rate",
    fields: @["heart_rate"],
    unit: "bpm",
    packing: pkU8,
    step: 1.0,
    lowest: 1,
    highest: 254,
  ),
  chCadence: ChannelSpec(
    # (zero is a reading: not pedalling)
    name: "cadence",
    title: "cadence",
    fields: @["cadence"],
    unit: "rpm",
    packing: pkU8,
    step: 1.0,
    lowest: 0,
    highest: 254,
  ),
  chTemperature: ChannelSpec(
    name: "temperature",
    title: "temperature",
    fields: @["temperature"],
    unit: "°C",
    packing: pkI8,
    step: 1.0,
    lowest: -100,
    highest: 100,
  ),
  chPower: ChannelSpec(
    name: "power",
    title: "power",
    fields: @["power"],
    unit: "W",
    packing: pkU16,
    step: 1.0,
    lowest: 0,
    highest: 65534,
  ),
  chSpeed: ChannelSpec(
    name: "speed",
    title: "speed",
    fields: @["enhanced_speed", "speed"],
    unit: "m/s",
    packing: pkU16,
    step: 0.001,
    lowest: 0,
    highest: 65534,
  ),
  chDistance: ChannelSpec(
    # the device's distance (a wheel's, or its own from GPS: dev/plot-activity.md says why it is preferred)
    name: "distance",
    title: "distance",
    fields: @["distance"],
    unit: "m",
    packing: pkIncrement,
    step: 0.01,
    lowest: 0,
    highest: 4_294_967_294,
  ),
]

func range*(p: Packing): Slice[int64] =
  ## The values the packing can hold.
  case p
  of pkU8:
    0'i64 .. 255'i64
  of pkI8:
    -128'i64 .. 127'i64
  of pkU16:
    0'i64 .. 65535'i64
  of pkIncrement:
    -(1'i64 shl 61) .. (1'i64 shl 61)
      # (so that no change between two of them, zigzagged, overflows)

func channelNamed*(name: string): Option[ChannelKind] =
  ## The channel stored under this name.
  for ch in ChannelKind:
    if specs[ch].name == name:
      return some(ch)

func value*(ch: ChannelKind, stored: int64): float =
  ## A stored value in the channel's unit.
  float(stored) * specs[ch].step
