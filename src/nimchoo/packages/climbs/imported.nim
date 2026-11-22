## The climbs of the new activities are found, made the climbs selection (as the activities are made the activities'), and
## named: what `climbs` does once an import has finished (the point
## `importer/after`), so that the wait is at the import, which already names the activities, and not at the first `nch climbs`
## or `nch map` after it.  (Finding the climbs and naming them are two steps, as in `nch climbs`: a climb that is not named
## cannot be asked for by name.)  Those still work out what is lacking before they show anything (it is idempotent: a second pass
## looks at nothing), so a database made before this, or an import whose last step failed, is caught up by them.

import std/[options, sequtils, strformat]
import ../../core/[errors, ids]
import ../importer/after
import ../user/session
import ../ui/vocabulary
import ./[attempts, chosen, naming, report, work]
import ../ui/units

{.push raises: [].}

proc workOutClimbs(
    st: Session, ids: seq[ActivityId], ctx: AfterContext
): seq[ImportReport] {.raises: [StoreError, DownloadError].} =
  ## Find the climbs of every activity not yet looked at (not only `ids`: a re-import catches up too), the two lines of
  ## `nch climbs` following it (`climbingLines`), then name those that have no name yet, as `nch climbs` does (`nameClimbs`).
  let worked = ensureClimbs(
    st,
    proc(done, total: int, soFar: Worked) {.closure, raises: [].} =
      ctx.show(climbingLines(done, total, soFar), false),
  )
  if worked.activities > 0:
    ctx.show(climbingLines(worked.activities, worked.activities, worked), true)
    result.add ImportReport(text: "climbs for " & workedText(worked))
  # the climbs of the new activities are the climbs selection, as they are the activities' (none: it is empty)
  let chosen = climbsOfActivities(st, ids.mapIt(int64(it)))
  st.replaceClimbSelection(chosen)
  result.add ImportReport(
    text:
      case chosen.len
      of 0:
        "selected no climbs (the new activities went up none)"
      of 1:
        "selected the climb of the new activities"
      else:
        fmt"selected the {chosen.len} climbs of the new activities",
    style: selectedStyle,
  )
  let named = nameClimbs(ctx.g, st, "import", ctx.say)
  if named.isSome and named.get.named + named.get.nothing > 0:
    result.add ImportReport(
      text:
        "named " & counted(named.get.named + named.get.nothing, "climb", "climbs") & ": " &
        $named.get.named & " with a name, " & $named.get.nothing & " with none near"
    )

let workNewClimbs* = AfterImport(
  run: workOutClimbs,
  failed:
    "the climbs of the new activities could not be worked out or named (`nch climbs` will do it)",
) ## after an import: the climbs of the activities it made, and their names
