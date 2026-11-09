## `nch activities --delete`: delete activities of the current user (the selection, or those the criteria find), with
## everything made from them.  Does nothing without -f; on a terminal it then counts down, in red, so there is time to press
## Ctrl-C, and shows how far it has got.  The file of an activity is forgotten too, so importing its folder again brings the
## activity back.  (The command line is `activities`'s; the planning and the deleting are in remove.nim.)

import std/strutils
import ../cli/catalog
import ../core/globals
import ../db/store
import ../core/errors
import ../core/logfile
import ../packages/ui/live
import ../packages/ui/style
import ../packages/confirm/confirm
import ./remove

{.push raises: [].}

func deletingLines*(done, total, files: int): seq[Line] =
  ## The two lines shown while the activities go, as the import's and the climbs' are (the counts in red here, not green):
  ## the first plain with the word in bold, the second the counts joined by grey dots.
  ##
  ##     deleting 340 / 1,381 activities
  ##     activities 340 · files 120
  @[
    @[
      span("deleting ", bold = true),
      span(
        insertSep($done, ',') & " / " & insertSep($total, ',') &
          (if total == 1: " activity" else: " activities")
      ),
    ],
    @[
      span("activities " & insertSep($done, ','), red),
      span(" · ", grey),
      span("files " & insertSep($files, ','), red),
    ],
  ]

proc runDelete*(
    g: Globals, st: Store, ids: seq[int64], force: bool, nothing: string
): int {.raises: [].} =
  ## Delete the activities `ids` (all of the current user's).  `nothing` is what to say if there are none.
  try:
    let plan = planDelete(st, ids)
    if plan.ids.len == 0:
      stdout.say nothing & "\n"
      return exitOk
    let what = describe(plan)
    if not force:
      return failure("nch activities", "would delete " & what & "; use -f to confirm")
    if canLive():
      countdown(newTerminalLive(), what, waitSeconds, sleepMs)
    # the count of what is gone so far, drawn only if the deleting takes more than a moment (as the import's)
    var shown = false
    var live = Live()
    let screen = canLive()
    if screen:
      live = newTerminalLive()
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
    var said = "deleted " & what
    if done.files > 0:
      said.add "; " & $done.files & (if done.files == 1: " file" else: " files") &
        " forgotten (importing them again would bring the activities back)"
    if done.kept > 0:
      said.add "; " & $done.kept & (if done.kept == 1: " file" else: " files") &
        " kept, with other activities in"
    g.log.log(lvInfo, $cmActivities, leDeleted, said & " from " & st.path)
    sayDeleted(said)
    exitOk
  except StoreError as e:
    failure("nch activities", e.msg)
