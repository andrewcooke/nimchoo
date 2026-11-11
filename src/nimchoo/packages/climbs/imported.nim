## The climbs of the new activities are worked out: what `climbs` does once an import has finished (the point
## `importer/after`), so that the wait is at the import, which already names the activities, and not at the first `nch climbs`
## or `nch map` after it.  Those still work out what is lacking before they show anything (it is idempotent: a second pass
## looks at nothing), so a database made before this, or an import whose last step failed, is caught up by them.

import std/options
import ../../core/errors
import ../importer/after
import ../user/session
import ./[report, work]

{.push raises: [].}

proc workOutClimbs(
    st: Session, ids: seq[int64], show: Show
): Option[ImportReport] {.raises: [StoreError].} =
  ## Every activity not yet looked at, not only `ids`: a re-import catches up too.  The two lines of `nch climbs` follow it
  ## (`climbingLines`), as they do there.
  let worked = ensureClimbs(
    st,
    proc(done, total: int, soFar: Worked) {.closure, raises: [].} =
      show(climbingLines(done, total, soFar), false),
  )
  if worked.activities == 0:
    return none(ImportReport)
  show(climbingLines(worked.activities, worked.activities, worked), true)
  some(ImportReport(text: "climbs for " & workedText(worked)))

let workNewClimbs* = AfterImport(
  run: workOutClimbs,
  failed:
    "the climbs of the new activities could not be worked out (`nch climbs` or `nch map` will do it)",
) ## after an import: the climbs of the activities it made
