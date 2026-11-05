## `nch climbs`: the climbs of the selected activities, with the time of each and where it ranks;
## or with `--sectors` every climb found.  The first time (and after an import) it works out the
## climbs of the activities that have not been looked at, and keeps them (see work.nim).

import std/[options, times]
import ../cli/[args, common]
import ../db/store
import ../errors
import ../names/open
import ../ui/[live, logfile]
import ./[naming, report, work]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] climbs
       nch [--db PATH] climbs --sectors

Show the climbs of the selected activities (see `nch list --save`): for each activity the climbs
it went up (where, how long, how much, how steep, and the category by the height gained), the
time it took, and where that ranks among the efforts of everyone on the same climb.  Times are
from the bottom to the top, stops included.

The climbs are found in the rides, once: the first time it works out those of every activity
that has not been looked at (about a minute for two thousand rides), and keeps them; after an
import it only looks at the new ones.  A climb found again in another ride is the same climb.

  --sectors     list every climb found instead, the biggest first: its length, height gained,
                gradient and category, how many times it has been ridden, the best time and
                whose it is, and your own best
  -h, --help    show this help
"""

type ClimbsArgs = object
  sectors, help: bool

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch climbs ARGS`; returns the exit status.
  var given = ClimbsArgs()
  let spec = Spec[ClimbsArgs](opts: @[
    flag(ClimbsArgs, ["-h", "--help"], help), flag(ClimbsArgs, ["--sectors"], sectors)])
  let why = parseOptions(args, spec, given)
  if why.len > 0: return usageError("nch climbs", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch climbs", e.msg)
  try:
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
    if given.sectors:
      let rows = allSectors(st)
      if rows.len == 0:
        stdout.say "no climbs found yet\n"
      else:
        for l in sectorLines(rows): stdout.say l & "\n"
      return exitOk
    if selectedActivities(st) == 0:
      stdout.say "nothing is selected: `nch list ... --save` chooses activities, `nch climbs --sectors` lists every climb\n"
      return exitOk
    let rows = selectedEfforts(st)
    if rows.len == 0:
      stdout.say "no climbs in the " & $selectedActivities(st) & " selected activities\n"
    else:
      for l in effortLines(rows, local()): stdout.say l & "\n"
    exitOk
  except StoreError, DownloadError:
    failure("nch climbs", getCurrentExceptionMsg())
