## An activity's active time: its riding less the breaks in which nothing was recorded (`stretch.timeBreaks`: manual,
## carried and pause), worked out by the database when it is asked for (37 ms for all of 1,117 activities, measured
## 2026-11-26), so that it is never kept beside the breaks it is made from.  Ours, not the device's: the file's timer total
## is not kept (it is wrong after a power cycle, and covers a whole file).  Pure.

import std/[sequtils, strutils]
import ./stretch

{.push raises: [].}

const kindList = toSeq(timeBreaks).mapIt("'" & $it & "'").join(", ")
  ## the kinds as SQL text: `'manual', 'carried', 'pause'`

func activeSql*(activity = "a"): string =
  ## SQL for the active time, in seconds, of the activity whose row is `activity` (a table's name or alias in the query,
  ## not a value).
  "(" & activity & ".riding_end_epoch - " & activity &
    ".riding_start_epoch - coalesce((select sum(b.end_epoch - b.start_epoch) from ride_break b where b.activity_id = " &
    activity & ".id and b.kind in (" & kindList & ")), 0))"
