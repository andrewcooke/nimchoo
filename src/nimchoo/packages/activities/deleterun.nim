## `nch activities --delete`: delete activities of the current user (the selection, or those the criteria find), with
## everything made from them.  Does nothing without -f; on a terminal it then counts down, in the bad style, so there is time to press
## Ctrl-C, and shows how far it has got.  The file of an activity is forgotten too, so importing its folder again brings the
## activity back.  (The command line is `activities`'s; the planning and the deleting are in remove.nim.)

import ./cmdname
import ../../core/globals
import ../db/store
import ../../core/errors
import ../../core/logfile
import ../ui/live
import ../ui/[markup, style]
import ../confirm/confirm
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
  @[
    styled"<em deleting >{d} / {t}",
    styled"<bad activities {d}><hide  · ><bad files {f}>",
  ]

proc runDelete*(
    g: Globals, st: Session, ids: seq[int64], force: Force, nothing: string
): int {.raises: [].} =
  ## Delete the activities `ids` (all of the current user's).  `nothing` is what to say if there are none.
  try:
    let plan = planDelete(st, ids)
    if plan.ids.len == 0:
      g.say osOut, nothing & "\n"
      return exitOk
    let what = describe(plan)
    if force == fNo:
      return
        failure(g, "nch activities", "would delete " & what & "; use `-f` to confirm")
    pause(g.theme, what, force)
    # the count of what is gone so far, drawn only if the deleting takes more than a moment (as the import's)
    var shown = false
    var live = Live()
    let screen = canLive()
    if screen:
      live = newTerminalLive(g.theme)
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
      said.add "; " & counted(done.files, "file", "files") &
        " forgotten (importing them again would bring the activities back)"
    if done.kept > 0:
      said.add "; " & counted(done.kept, "file", "files") &
        " kept, with other activities in"
    g.log.log(lvInfo, commandName, leDeleted, said & " from " & st.path)
    sayDeleted(g, said)
    exitOk
  except StoreError as e:
    failure(g, "nch activities", e.msg)
