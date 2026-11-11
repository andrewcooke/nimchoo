## The climbs of the new activities are worked out: what `climbs` does once an import has finished (the point
## `importer/after`), so that the wait is at the import, which already names the activities, and not at the first `nch climbs`
## or `nch map` after it.  Those still work out what is lacking before they show anything (it is idempotent: a second pass
## looks at nothing), so a database made before this, or an import whose last step failed, is caught up by them.

import std/options
import ../../core/errors
import ../importer/[after, sinks]
import ../user/session
import ./work

{.push raises: [].}

proc workOutClimbs(
    st: Session, ids: seq[int64]
): Option[ImportReport] {.raises: [StoreError].} =
  ## Every activity not yet looked at, not only `ids`: a re-import catches up too.
  let worked = ensureClimbs(st)
  if worked.activities == 0:
    return none(ImportReport)
  some(
    ImportReport(
      text:
        "worked out the climbs of " & plural(
          worked.activities, "activity", "activities"
        ) & ": " & plural(worked.sectors, "new climb", "new climbs")
    )
  )

let workNewClimbs* = AfterImport(
  run: workOutClimbs,
  failed:
    "the climbs of the new activities could not be worked out (`nch climbs` or `nch map` will do it)",
) ## after an import: the climbs of the activities it made
