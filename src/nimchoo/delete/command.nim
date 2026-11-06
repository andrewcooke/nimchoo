## `nch delete`: delete the selected activities (see `nch activities --select`) of the current user, with everything made from
## them.  Does nothing without --force; on a terminal it then counts down, in red, so there is time to press Ctrl-C.
## The file of an activity is forgotten too, so importing its folder again brings the activity back.

import std/strutils
import ../cli/[args, common]
import ../db/store
import ../errors
import ../ui/[live, logfile, style]
import ../user/wipe
import ./remove

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] delete -f

Delete the activities of the selection (what `nch activities --select` kept; `nch activities` shows it) that belong to
the current user, and everything made from them: coordinates, route, heart rate, impulses, efforts.  The climbs
found in them stay (they are shared), and so do the names on those.

An activity of another user in the selection is left alone (the message says how many).

The activity's file is forgotten as well: importing its folder again would bring the activity back.  (A file
with several activities is forgotten when the last of them goes.)

Nothing is deleted without -f.  On a terminal there are then 5 seconds in which to press Ctrl-C.

  -f, --force   really do it
  -h, --help    show this help
"""

type DeleteArgs = object
  force, help: bool

func deletingLines*(done, total, files: int): seq[Line] =
  ## The two lines shown while the activities go, as the import's and the climbs' are (the counts in red here, not green):
  ## the first plain with the word in bold, the second the counts joined by grey dots.
  ##
  ##     deleting 340 / 1,381 activities
  ##     activities 340 · files 120
  @[@[span("deleting ", bold = true),
      span(insertSep($done, ',') & " / " & insertSep($total, ',') & (if total == 1: " activity" else: " activities"))],
    @[span("activities " & insertSep($done, ','), red), span(" · ", grey), span("files " & insertSep($files, ','), red)]]

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch delete ARGS`; returns the exit status.
  var given = DeleteArgs()
  let spec = Spec[DeleteArgs](opts: @[
    flag(DeleteArgs, ["-h", "--help"], help), flag(DeleteArgs, ["-f", "--force"], force)])
  let why = parseOptions(args, spec, given)
  if why.len > 0: return usageError("nch delete", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch delete", e.msg)
  try:
    let plan = planDelete(st)
    let others = if plan.others == 0: "" else:
      $plan.others & (if plan.others == 1: " selected activity of another user is left alone" else: " selected activities of other users are left alone")
    if plan.ids.len == 0:
      stdout.say (if plan.others > 0: "none of the selected activities is yours: " & others & "\n"
                  else: "nothing is selected: `nch activities CRITERIA --select` chooses activities\n")
      return exitOk
    let what = describe(plan)
    if not given.force:
      return failure("nch delete", "would delete " & what & (if others.len > 0: " (" & others & ")" else: "") &
                     "; use -f to confirm")
    if canLive():
      countdown(newTerminalLive(), what, waitSeconds, sleepMs)
    # the count of what is gone so far, drawn only if the deleting takes more than a moment (as the import's)
    var shown = false
    var live = Live()
    let screen = canLive()
    if screen: live = newTerminalLive()
    let done = deleteActivities(st, plan, proc(n, total, files: int) {.closure, raises: [].} =
      if screen and (n == total or live.due()):
        shown = true
        live.show(deletingLines(n, total, files)))
    if screen:
      if shown: live.keep(deletingLines(plan.ids.len, plan.ids.len, done.files))
      else: live.finish()
    var said = "deleted " & what
    if done.files > 0:
      said.add "; " & $done.files & (if done.files == 1: " file" else: " files") & " forgotten (importing them again would bring the activities back)"
    if done.kept > 0:
      said.add "; " & $done.kept & (if done.kept == 1: " file" else: " files") & " kept, with other activities in"
    if others.len > 0: said.add "; " & others
    g.log.log(lvInfo, "delete", leDeleted, said & " from " & st.path)
    stdout.say "done: " & said & "\n"
    exitOk
  except StoreError as e:
    failure("nch delete", e.msg)
