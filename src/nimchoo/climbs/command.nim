## `nch climbs`: the climbs.  With no arguments the climbs of the selected activities, with the time of each and where
## it ranks; `--all` every climb found; `--edit NAME` changes one (its name, or whether it is hidden); `--retired` and
## `--duplicates` are lists for tidying.  The first time (and after an import) it works out the climbs of the activities
## that have not been looked at, and keeps them (see work.nim).  The climbs are shared by all users.

import std/[options, times]
import ../cli/common
import ../db/store
import ../errors
import ../names/open
import ../ui/[live, logfile]
import ../user/wipe
import ./[duplicates, edit, naming, params, report, work]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] climbs
       nch [--db PATH] [--user NAME] climbs --all
       nch climbs --all --delete -f
       nch climbs --edit NAME --rename NEW
       nch climbs --edit NAME --auto
       nch climbs --edit NAME --retire
       nch climbs --edit NAME --unretire
       nch climbs --retired
       nch climbs --duplicates

Show the climbs of the selected activities (see `nch activities --select`): for each activity the climbs
it went up (where, how long, how much, how steep, and the category by the height gained), the
time it took, and where that ranks among the efforts of everyone on the same climb.  Times are
from the bottom to the top, stops included.

The climbs are found in the rides, once: the first time it works out those of every activity
that has not been looked at (about a minute for two thousand rides), and keeps them; after an
import it only looks at the new ones.  A ride that goes over part of a climb but not all of it
makes a climb of its own.

  --all           every climb found instead, the biggest first: its category, length, height gained
                  and gradient, how many times it has been ridden, the best time and whose it is, your
                  own best, and "manual" against a name given by a person
  --delete        (with --all) delete every climb found, with the efforts on them (of every user), and start again:
                  the next `nch climbs` works them out again from the rides.  Names given by hand are lost
                  (the message says how many).  Needs -f; on a terminal there are then 5 seconds in which to
                  press Ctrl-C.  The climbs are never deleted one at a time: `--edit NAME --retire` hides one
  --edit NAME     change that climb, with one of the following.  NAME is a climb's name as `--all` shows
                  it, "(n/m)" included where several share a name: "Morro La Cabra (1/3)"
    --rename NEW    give it the name NEW (any words; at most 60 characters; not ending in "(n/m)",
                    which is added by the program when climbs share a name).  The name is kept: the
                    program never changes it.  Several climbs may have the same name
    --auto          forget the name; it is named again at once from the places near it (or by the
                    next `nch climbs` if the names cannot be had)
    --retire        hide the climb from the lists, as a segment can be hidden on Strava.  Nothing is
                    deleted: it keeps its efforts, still takes those of new rides, and keeps its place
                    in the (n/m) of its name, so the gap shows
    --unretire      show it again
  --retired       list the retired climbs
  --duplicates    list the climbs that largely overlap (more than half of each lies within 25 m of the
                  other), the most ridden first, with the command to hide each of the others
  -h, --help      show this help

The climbs are shared by all users; the ranks count everyone's efforts.  (`--user` says whose selection
is shown, and whose best time is "yours".)
"""

func noteRetired(count: int): string =
  $count & (if count == 1: " climb is retired" else: " climbs are retired") &
    " (hidden; `nch climbs --retired` shows them): the numbers in the names include them\n"

proc editClimb(g: Globals, st: Store, p: Params): int {.raises: [StoreError].} =
  ## `--edit NAME` with one thing to change.
  let id = findShown(st, p.name)
  let was = shownName(st, id)
  var said: string
  if p.retire or p.unretire:
    setRetired(st, id, p.retire)
    said = was & (if p.retire: " is retired: hidden from the lists (`nch climbs --retired` shows it; --unretire brings it back)"
                  else: " is shown again")
  elif p.auto:
    setAuto(st, id)
    said = was & ": the name is forgotten"
    let names = openNames(g, st, "climbs", proc(line: string) {.closure, raises: [].} = stderr.say line & "\n")
    if names.isSome:
      try:
        discard ensureSectorNames(st, names.get)
        said = was & " is now called " & shownName(st, id)
      except DownloadError as e:
        said.add "; " & e.msg & " (the next `nch climbs` makes one)"
  else:
    rename(st, id, p.rename)
    said = was & " is now called " & shownName(st, id)
  g.log.log(lvInfo, "climbs", leSaved, said)
  stdout.say said & "\n"
  exitOk

proc deleteClimbs(g: Globals, st: Store, force: bool): int {.raises: [StoreError].} =
  ## `--all --delete`: every climb and the efforts on them go; the next `nch climbs` works them out again.
  let what = describe(countClimbs(st))
  if not force:
    return failure("nch climbs", "would delete " & what & "; use -f to confirm")
  if canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
  clearClimbs(st)
  g.log.log(lvInfo, "climbs", leDeleted, "deleted " & what & " from " & st.path)
  stdout.say "done: deleted " & what & "\n"
  exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch climbs ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch climbs", usage, p.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch climbs", e.msg)
  try:
    # the lists for tidying, and the changes, need no working out of climbs
    if p.duplicates:
      for l in duplicateLines(duplicateGroups(st)): stdout.say l & "\n"
      return exitOk
    if p.retired:
      let rows = allSectors(st, retired = true)
      if rows.len == 0:
        stdout.say "no climbs are retired\n"
      else:
        for l in sectorLines(rows): stdout.say l & "\n"
      return exitOk
    if p.edit:
      return editClimb(g, st, p)
    if p.delete:
      return deleteClimbs(g, st, p.force)
    var worked: Worked
    if canLive():
      # two lines that follow the work and stay on the screen at the end (as the import's do)
      let live = newTerminalLive()
      var shown = false
      worked = ensureClimbs(st, proc(done, total: int, soFar: Worked) {.closure, raises: [].} =
        shown = true
        if done == total or live.due(): live.show(climbingLines(done, total, soFar)))
      if shown: live.keep(climbingLines(worked.activities, worked.activities, worked))
      else: live.finish()
    else:
      worked = ensureClimbs(st)
    if worked.activities > 0:
      stderr.say doneLine(worked) & "\n"
      g.log.log(lvInfo, "climbs", leDone, "worked out " & $worked.activities & " activities: " &
                $worked.sectors & " new climbs, " & $worked.efforts & " efforts")
    # names for the climbs that have none yet: from the places near them, fetched the first time
    let names = openNames(g, st, "climbs", proc(line: string) {.closure, raises: [].} = stderr.say line & "\n")
    if names.isSome:
      let named = ensureSectorNames(st, names.get)
      if named.named + named.nothing > 0:
        g.log.log(lvInfo, "climbs", leDone, "named " & $named.named & " climbs (" & $named.nothing & " with no name near)")
    if p.all:
      let rows = allSectors(st)
      if rows.len == 0:
        stdout.say "no climbs found yet\n"
      else:
        for l in sectorLines(rows): stdout.say l & "\n"
        let hidden = countRetired(st)
        if hidden > 0: stdout.say noteRetired(hidden)
      return exitOk
    if selectedActivities(st) == 0:
      stdout.say "nothing is selected: `nch activities CRITERIA --select` chooses activities, `nch climbs --all` lists every climb\n"
      return exitOk
    let rows = selectedEfforts(st)
    if rows.len == 0:
      stdout.say "no climbs in the " & $selectedActivities(st) & " selected activities\n"
    else:
      for l in effortLines(rows, local()): stdout.say l & "\n"
    exitOk
  except StoreError, DownloadError:
    failure("nch climbs", getCurrentExceptionMsg())
