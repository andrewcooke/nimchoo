## The tags an import gives an activity, from what its file says: for now its sport, `sport:SPORT:SUB-SPORT`
## (`sport:cycling:road`), or `sport:SPORT` when the sub-sport is not recorded or "generic"; no sport, no tag.  An import
## step (`importer/steps`): the importer calls `write` for each activity, inside the transaction that imports it, after
## the activity's row is written.

import std/[options, strformat]
import ../../core/[errors, ids]
import ../db/statement
import ../importer/channel
import ../util/warnings/warnings
import ./tag

{.push raises: [].}

func sportTag*(sport, subSport: string): Option[Tag] =
  ## The sport as a tag (the FIT profile's names: lower case, `_` for a space), or none if there is no sport.  A name that
  ## cannot be a tag (it never is in the profile) gives none too.
  if sport.len == 0:
    return none(Tag)
  let text =
    if subSport.len == 0 or subSport == "generic":
      fmt"sport:{sport}"
    else:
      fmt"sport:{sport}:{subSport}"
  parseTag(text).tag

proc write(
    db: DbConn, activity: ActivityId, samples: Samples, warnings: var seq[Warning]
): int {.nimcall, raises: [StoreError].} =
  let row = db.queryOne(
    tuple[sport, subSport: string],
    "select coalesce(sport, ''), coalesce(sub_sport, '') from activity where id = :activity",
    activity = activity,
  )
  doAssert row.isSome, "the importer writes the activity before its steps"
  let t = sportTag(row.get.sport, row.get.subSport)
  if t.isSome:
    result = db.addTags(activity, [t.get])

let tagsStep* = ImportStep(label: "tag", labels: "tags", channels: @[], write: write)
  ## The import step of this package (`package.nim` contributes it).
