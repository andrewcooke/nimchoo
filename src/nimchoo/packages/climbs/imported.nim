## The climbs of the new activities are found and named: what `climbs` does once an import has finished (the point
## `importer/after`), so that the wait is at the import, which already names the activities, and not at the first `nch climbs`
## or `nch map` after it.  (Finding the climbs and naming them are two steps, as in `nch climbs`: a climb that is not named
## cannot be asked for by name.)  Those still work out what is lacking before they show anything (it is idempotent: a second pass
## looks at nothing), so a database made before this, or an import whose last step failed, is caught up by them.

import std/options
import ../../core/errors
import ../importer/[after, sinks]
import ../user/session
import ./[naming, report, work]

{.push raises: [].}

proc workOutClimbs(
    st: Session, ids: seq[int64], ctx: AfterContext
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
  let named = nameClimbs(ctx.g, st, "import", ctx.say)
  if named.isSome and named.get.named + named.get.nothing > 0:
    result.add ImportReport(
      text:
        "named " & plural(named.get.named + named.get.nothing, "climb", "climbs") & ": " &
        $named.get.named & " with a name, " & $named.get.nothing & " with none near"
    )

let workNewClimbs* = AfterImport(
  run: workOutClimbs,
  failed:
    "the climbs of the new activities could not be worked out or named (`nch climbs` will do it)",
) ## after an import: the climbs of the activities it made, and their names
