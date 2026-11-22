## What `climbs` offers `nch activities`: the criterion `--climbs TEXT...`, the activities that have an effort on a climb
## whose name holds the text.  It is contributed to the point `activities/criteria` (see package.nim); the condition reads
## `effort`, a table of this package, which `activities` could not read by itself.

import std/[options, strutils]
import ../../core/errors
import ../activities/criterion
import ../db/sqltext
import ../user/session
import ../util/args/args
import ./[completion, report]

{.push raises: [].}

func onClimbs*(ids: seq[int64]): Sql =
  ## True for the activities that have an effort on one of these climbs.
  sqlOf(
    "exists (select 1 from effort e where e.activity_id = a.id and e.sector_id in (select value from json_each(:climbs)))"
  )
    .with("climbs", jsonList(ids))

proc resolveClimbs(
    st: Session, values: seq[string]
): Resolution {.raises: [StoreError].} =
  ## The climbs whose name as shown ("Farellones₂", retired ones too) holds each text, whatever its case and accents
  ## ("farellones 2" and "farellones2" mean "farellones₂" as well).  A text
  ## that no climb has is an error.
  var texts: seq[string]
  for v in values:
    if v.strip.len > 0:
      texts.add v.strip
  if texts.len == 0:
    raiseStore("`--climbs` needs some text")
  var ids: seq[int64]
  for (t, hits) in climbsNamed(st, texts, retiredToo = true):
    if hits.len == 0:
      raiseStore(
        "no climb has '" & t &
          "' in its name or is numbered so (`nch climbs --all` lists them)"
      )
    for id in hits:
      if id notin ids:
        ids.add id
  result.condition = onClimbs(ids)

let climbCriterion* = Criterion(
  doc: OptDoc(
    names: @["--climbs"],
    metavar: some("TEXT..."),
    help: ~"activities that have an effort on a climb whose name (as `nch climbs --all` shows it) contains any of the TEXTs: `--climbs farellones` (all of them), `--climbs farellones₂` (or \"farellones 2\") (one); a whole number that no name holds is a climb's number (`--climbs 62`); retired climbs too.  It is an error if no climb has the text",
    arity: aList,
    completion: completesFrom(completeClimbWords),
  ),
  resolve: resolveClimbs,
) ## the criterion `--climbs`
