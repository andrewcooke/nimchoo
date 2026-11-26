## `nch activities --delete`: delete activities of the current user (the selection, or those the criteria find), with
## everything made from them.  It asks first, saying what would go (`core/ask`), and on a terminal shows how far it has
## got.  The file of an activity is forgotten too, so importing its folder again brings the activity back.  (The command
## line is `activities`'s; the planning and the deleting are in `importer/remove.nim`; the question is here, as it counts
## the sports, which are tags, and `importer` is below `tags`.)

import std/[algorithm, options, strformat, strutils, tables, times]
import ./cmdname
import ../../core/[ask, globals]
import ../db/[statement, store]
import ../importer/describe
import ../tags/sport
import ../../core/errors
import ../../core/logfile
import ../ui/live
import ../ui/style
import ../../core/markup
import ../importer/remove
import ../user/session
import ../ui/units

{.push raises: [].}

func deletingLines*(done, total, files: int): seq[Line] =
  ## The two lines shown while the activities go, as the import's and the climbs' are (the counts bad here, not good):
  ## the first plain with the word emphasised, the second the counts joined by hidden dots.
  ##
  ##     deleting 340 / 1,381 activities
  ##     activities 340 · files 120
  let (d, f) = (count(done), count(files))
  let t = counted(total, "activity", "activities")
  @[~"<em deleting >{d} / {t}", ~"<bad activities {d}><hide  · ><bad files {f}>"]

proc sportsOf*(
    st: Session, ids: seq[ActivityId]
): seq[(string, int)] {.raises: [StoreError].} =
  ## How many of the activities are of each sport (`tags/sport`; "" none), the most first, then by name.
  var n = initCountTable[string]()
  for (text) in st.db.query(
    (string,),
    "select " & sportSql() &
      " from activity a where a.id in (select value from json_each(:ids))",
    ids = jsonList(ids),
  ):
    n.inc sportParts(text).sport
  for sport, k in n:
    result.add (sport, k)
  result.sort(
    proc(a, b: (string, int)): int =
      result = cmp(b[1], a[1])
      if result == 0:
        result = cmp(a[0], b[0])
  )

proc question*(p: Plan, sports: seq[(string, int)], zone: Timezone): string =
  ## "12 activities (cycling 9, running 3) from 2018-07-01 to 2026-10-30": the days in `zone`, and the sports and
  ## counts (`sportsOf`), as the list of activities writes them (`importer/describe`).
  let n = p.ids.len
  result = counted(n, "activity", "activities")
  if n == 0:
    return
  var sp: seq[string]
  for (sport, k) in sports:
    let (s, c) = (sportText(sport, "", false), count(k))
    sp.add fmt"{s} {c}"
  let (a, b) = (dateText(p.first, zone), dateText(p.last, zone))
  let days =
    if a == b:
      fmt"on {a}"
    else:
      fmt"from {a} to {b}"
  let listed = sp.join(", ")
  result.add fmt" ({listed}) {days}"

proc runDelete*(
    g: Globals,
    st: Session,
    ids: seq[int64],
    yOrN: YesOrNo,
    nothing: Line,
    zone: Timezone,
): int {.raises: [].} =
  ## (`zone`: the one the list of activities uses, for the days the message names.)
  ## Delete the activities `ids` (all of the current user's).  `nothing` is what to say if there are none.
  try:
    let plan = planDelete(st, ids)
    if plan.ids.len == 0:
      g.warn nothing # (as an empty selection is everywhere: a warning, not a failure)
      return exitOk
    let what = question(plan, sportsOf(st, plan.ids), zone)
    let refused = askDelete(g, what, yOrN)
    if refused.isSome:
      return refused.get
    # the count of what is gone so far, drawn only if the deleting takes more than a moment (as the import's)
    var shown = false
    var live = Live()
    let screen = canLive()
    if screen:
      live = newTerminalLive(paintOf(g, osErr))
    let done = deleteActivities(
      st,
      plan,
      proc(n, total, files: int) {.closure, raises: [].} =
        if screen and (n == total or live.due()):
          shown = true
          live.show(deletingLines(n, total, files))
      ,
    )
    st.reclaim()
    if screen:
      if shown:
        live.keep(deletingLines(plan.ids.len, plan.ids.len, done.files))
      else:
        live.finish()
    var said = fmt"deleted {what}"
    if done.files > 0:
      let files = counted(done.files, "file", "files")
      said.add fmt"; {files} forgotten (importing them again would bring the activities back)"
    if done.kept > 0:
      let files = counted(done.kept, "file", "files")
      said.add fmt"; {files} kept, with other activities in"
    g.log.log(lvInfo, commandName, leDeleted, fmt"{said} from {st.path}")
    sayDeleted(g, said)
    exitOk
  except StoreError as e:
    failure(g, "nch activities", e.msg)
