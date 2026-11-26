## The channels of an import: for each channel (kinds.nim), the values of its record fields, one reading per second at most,
## kept as a row of `channel_series` when there is any.  (The importer calls `write` for each activity, inside the
## transaction that imports it.)

import std/[algorithm, math, sets, strformat, tables]
import ../ui/units
import ../util/warnings/warnings
import ../db/statement
import ../importer/channel
import ./[kinds, series]
import ../../core/errors
import ../fit/time
import ../../core/ids

{.push raises: [].}

func readings*(
    samples: Samples, ch: ChannelKind
): tuple[rows: seq[(UnixTime, int64)], dropped: int] =
  ## (time, stored value) in time order, and how many values were not readings of the channel (outside its stored range,
  ## once rounded to its step).  Where a record has several of the channel's fields, the first in its list wins.
  let spec = specs[ch]
  var seen: HashSet[int64]
  for field in spec.fields:
    for x in samples.getOrDefault(field):
      if int64(x.t) in seen:
        continue
      seen.incl int64(x.t)
      # (a NaN must not reach the arithmetic: with checks on, that is a Defect)
      if x.v.classify in {fcNan, fcInf, fcNegInf}:
        inc result.dropped
        continue
      let v = round(x.v / spec.step)
      if v >= float(spec.lowest) and v <= float(spec.highest):
        result.rows.add (x.t, int64(v))
      else:
        inc result.dropped
  result.rows.sort(
    proc(a, b: (UnixTime, int64)): int =
      cmp(int64(a[0]), int64(b[0]))
  )

proc write(
    db: DbConn, activityId: ActivityId, input: StepInput, warnings: var seq[Warning]
): int {.nimcall, raises: [StoreError].} =
  for ch in ChannelKind:
    let spec = specs[ch]
    let (rows, dropped) = readings(input.samples, ch)
    if dropped > 0:
      let
        values = counted(dropped, "value", "values")
        lo = value(ch, spec.lowest)
        hi = value(ch, spec.highest)
      warnings.add wkBadReading,
        0, fmt"{spec.title}: {values} not from {lo:g} to {hi:g} {spec.unit} (dropped)"
    if rows.len == 0:
      continue
    let arrays = pack(ch, rows)
    let st = prepareStmt(
      db,
      "insert into channel_series(activity_id, channel, start_epoch, n_readings, gaps_s, readings) values (?, ?, ?, ?, ?, ?)",
    )
    st.bindInt(1, activityId)
    st.bindText(2, spec.name)
    st.bindInt(3, int64(arrays.start))
    st.bindInt(4, arrays.count)
    st.bindBlob(5, arrays.gaps)
    st.bindBlob(6, arrays.values)
    st.run()
    result += rows.len

func allFields(): seq[string] =
  for ch in ChannelKind:
    for f in specs[ch].fields:
      if f notin result:
        result.add f

let channelsStep* = ImportStep(
  label: "channel reading",
  labels: "channel readings",
  channels: allFields(),
  write: write,
)
