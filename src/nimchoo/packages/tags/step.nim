## The tags an import gives an activity: its sport, from what its file says, `sport:SPORT:SUB-SPORT`
## (`sport:cycling:road`), or `sport:SPORT` when the sub-sport is not recorded or "generic" (no sport, no tag); and what
## the template of the import path caught (`importer/paths.nim`): `{bike}` that caught "cotic" is `bike:cotic`, `{}` that
## caught "foo" is `foo`.  What cannot be a tag (a space, a dot) is a warning, and no tag.  An import step
## (`importer/steps`): the importer calls `write` for each activity, inside the transaction that imports it, after the
## activity's row is written.

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

func labelTag*(l: PathLabel): tuple[tag: Option[Tag], problem: Option[string]] =
  ## What a template caught, as a tag (`key:value`, or the value alone), or what is wrong with it.
  let text =
    if l.key.isSome:
      fmt"{l.key.get}:{l.value}"
    else:
      l.value
  let r = parseTag(text)
  (r.tag, r.problem)

proc write(
    db: DbConn,
    activity: ActivityId,
    samples: Samples,
    labels: seq[PathLabel],
    warnings: var seq[Warning],
): int {.nimcall, raises: [StoreError].} =
  let row = db.queryOne(
    tuple[sport, subSport: string],
    "select coalesce(sport, ''), coalesce(sub_sport, '') from activity where id = :activity",
    activity = activity,
  )
  doAssert row.isSome, "the importer writes the activity before its steps"
  var tags: seq[Tag]
  let t = sportTag(row.get.sport, row.get.subSport)
  if t.isSome:
    tags.add t.get
  for l in labels:
    let lt = labelTag(l)
    if lt.tag.isSome:
      tags.add lt.tag.get
    else:
      warnings.add wkPathTag, 0, fmt"the path gave no tag: {lt.problem.get}"
  result = db.addTags(activity, tags)

let tagsStep* = ImportStep(label: "tag", labels: "tags", channels: @[], write: write)
  ## The import step of this package (`package.nim` contributes it).
