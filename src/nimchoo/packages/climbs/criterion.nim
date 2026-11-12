## What `climbs` offers `nch activities`: the criterion `--climbs TEXT...`, the activities that have an effort on a climb
## whose name holds the text.  It is contributed to the point `activities/criteria` (see package.nim); the condition reads
## `effort`, a table of this package, which `activities` could not read by itself.

import std/[options, strutils, tables]
import ../../core/errors
import ../activities/criterion
import ../db/sqltext
import ../text/fold/fold
import ../user/session
import ../util/args/args
import ./[completion, display, report]

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
    raiseStore("--climbs needs some text")
  var ids: seq[int64]
  let shown = shownNames(st)
  for t in texts:
    var found = false
    for id, name in shown:
      for form in ordinalForms(t):
        if foldText(name).contains(foldText(form)):
          found = true
          if id notin ids:
            ids.add id
    if not found:
      let n = climbNumber(t)
      if n.isSome and n.get in shown:
        found = true
        ids.add n.get
    if not found:
      raiseStore(
        "no climb has '" & t &
          "' in its name or is numbered so (`nch climbs --all` lists them)"
      )
  result.condition = onClimbs(ids)

let climbCriterion* = Criterion(
  doc: OptDoc(
    names: @["--climbs"],
    metavar: "TEXT...",
    help:
      "activities that have an effort on a climb whose name (as `nch climbs --all` shows it) contains any of the TEXTs: --climbs farellones (all of them), --climbs farellones₂ (or \"farellones 2\") (one); a whole number that no name holds is a climb's number (--climbs 62); retired climbs too.  It is an error if no climb has the text",
    arity: aList,
    completion: completesFrom(completeClimbWords),
  ),
  resolve: resolveClimbs,
) ## the criterion `--climbs`
