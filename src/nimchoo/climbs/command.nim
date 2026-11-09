## `nch climbs`: the climbs.  With no arguments the climbs of the selected activities, with the time of each and where
## it ranks; `--all` every climb found; `--edit NAME` changes one (its name, or whether it is hidden); `--retired` and
## `--duplicates` are lists for tidying.  The first time (and after an import) it works out the climbs of the activities
## that have not been looked at, and keeps them (see work.nim).  The climbs are shared by all users.

import std/[options, strutils, times]
import ../cli/common
import ../db/store
import ../core/errors
import ../names/open
import ../ui/[live, logfile, style]
import ../user/wipe
import ./[attempts, duplicates, edit, naming, params, report, work]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] climbs [-v] [--everyone]
       nch [--db PATH] [--user NAME] climbs --name TEXT... [-v] [--everyone]
       nch climbs --all
       nch climbs --all --delete -f
       nch climbs --edit NAME --rename NEW
       nch climbs --edit NAME --auto
       nch climbs --edit NAME --retire
       nch climbs --edit NAME --unretire
       nch climbs --retired
       nch climbs --duplicates

Show the climbs the selected activities went up (see `nch activities --select`), each the standard way (name,
category by the height gained, length, gain, gradient), then how you did on it: your best time and when, your best time
on the selected rides (blue) and when, where that one ranks among your own attempts, and how many times you rode it.
All your attempts count in the best and the rank, not only those of the selected rides.  Times are from the bottom to the top, stops included.

The climbs are found in the rides, once: the first time it works out those of every activity
that has not been looked at (about a minute for two thousand rides), and keeps them; after an
import it only looks at the new ones.  A ride that goes over part of a climb but not all of it
makes a climb of its own.

  --name TEXT...  the climbs whose name holds the text (any of them; case and accents do not matter; the
                  number counts: `--name farellones₂`, which `--name "farellones 2"` also means), among all the
                  climbs, not those of the selected rides
  -v, --verbose   list the attempts under each climb, the fastest first, each with its rank (those of the selected
                  rides in blue)
  --everyone      the people instead of your attempts: how many have ridden each climb, the fastest and who,
                  and where your best time comes among everyone's best times ("4 of 6"); with -v each person's
                  best.  (The personal rank and this one are never shown together.)
  --all           just the climbs found, the biggest first: category, length, height gained and gradient, how
                  many times it has been ridden, and "manual" against a name given by a person
  --delete        (with --all) delete every climb found, with the efforts on them (of every user), and start again:
                  the next `nch climbs` works them out again from the rides.  Names given by hand are lost
                  (the message says how many).  Needs -f; on a terminal there are then 5 seconds in which to
                  press Ctrl-C.  The climbs are never deleted one at a time: `--edit NAME --retire` hides one
  --edit NAME     change that climb, with one of the following.  NAME is a climb's name as `--all` shows
                  it, its number included where several share a name: "Morro La Cabra₁" ("Morro La Cabra 1" and
                  "Morro La Cabra1" do as well).  The number is kept: it never changes
    --rename NEW    give it the name NEW (any words; at most 60 characters; not ending in a subscript
                    number, which the program adds when climbs share a name).  The name is kept: the
                    program never changes it.  Several climbs may have the same name
    --auto          forget the name; it is named again at once from the places near it (or by the
                    next `nch climbs` if the names cannot be had)
    --retire        hide the climb from the lists, as a segment can be hidden on Strava.  Nothing is
                    deleted: it keeps its efforts, still takes those of new rides, and keeps its number,
                    so the gap shows
    --unretire      show it again
  --retired       list the retired climbs
  --duplicates    list the climbs that largely overlap (more than half of each lies within 25 m of the
                  other), the most ridden first, with the command to hide each of the others
  -h, --help      show this help

The climbs are shared by all users.  (`--user` says whose selection is used, and whose attempts are "yours".)
"""

func noteRetired(count: int): string =
  $count & (if count == 1: " climb is retired" else: " climbs are retired") &
    " (hidden; `nch climbs --retired` shows them): the numbers in the names include them\n"

func damagedText(n: Named): string =
  ## What to say about climbs that were not named because their route cannot be read.
  $n.damaged.len & (if n.damaged.len == 1: " climb has" else: " climbs have") &
    " a route that cannot be read (damaged data) and " &
    (if n.damaged.len == 1: "was" else: "were") & " not named: " & n.damaged.join(", ")

proc editClimb(g: Globals, st: Store, p: Params): int {.raises: [StoreError].} =
  ## `--edit NAME` with one thing to change.
  let id = findShown(st, p.name)
  let was = shownName(st, id)
  var said: string
  if p.retire or p.unretire:
    setRetired(st, id, p.retire)
    said =
      was & (
        if p.retire:
        " is retired: hidden from the lists (`nch climbs --retired` shows it; --unretire brings it back)"
        else: " is shown again"
      )
  elif p.auto:
    setAuto(st, id)
    said = was & ": the name is forgotten"
    let names = openNames(
      g,
      st,
      cmClimbs,
      proc(line: string) {.closure, raises: [].} =
        stderr.say line & "\n"
      ,
    )
    if names.isSome:
      try:
        let named = ensureSectorNames(st, names.get)
        said = was & " is now called " & shownName(st, id)
        if named.damaged.len > 0:
          said.add " (" & damagedText(named) & ")"
      except DownloadError as e:
        said.add "; " & e.msg & " (the next `nch climbs` makes one)"
  else:
    rename(st, id, p.rename)
    said = was & " is now called " & shownName(st, id)
  g.log.log(lvInfo, cmClimbs, leSaved, said)
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
  st.reclaim()
  g.log.log(lvInfo, cmClimbs, leDeleted, "deleted " & what & " from " & st.path)
  sayDeleted("deleted " & what)
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
      for l in duplicateLines(duplicateGroups(st)):
        stdout.say l & "\n"
      return exitOk
    if p.retired:
      let rows = allSectors(st, retired = true)
      if rows.len == 0:
        stdout.say "no climbs are retired\n"
      else:
        for l in sectorLines(rows):
          stdout.say l & "\n"
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
      worked = ensureClimbs(
        st,
        proc(done, total: int, soFar: Worked) {.closure, raises: [].} =
          shown = true
          if done == total or live.due():
            live.show(climbingLines(done, total, soFar))
        ,
      )
      if shown:
        live.keep(climbingLines(worked.activities, worked.activities, worked))
      else:
        live.finish()
    else:
      worked = ensureClimbs(st)
    if worked.activities > 0:
      stderr.say doneLine(worked) & "\n"
      g.log.log(
        lvInfo,
        cmClimbs,
        leDone,
        "worked out " & $worked.activities & " activities: " & $worked.sectors &
          " new climbs, " & $worked.efforts & " efforts",
      )
    # names for the climbs that have none yet: from the places near them, fetched the first time
    let names = openNames(
      g,
      st,
      cmClimbs,
      proc(line: string) {.closure, raises: [].} =
        stderr.say line & "\n"
      ,
    )
    if names.isSome:
      let named = ensureSectorNames(st, names.get)
      if named.damaged.len > 0:
        stderr.say "warning: " & damagedText(named) & "\n"
        g.log.log(lvWarn, cmClimbs, leAdvisory, damagedText(named))
      if named.named + named.nothing > 0:
        g.log.log(
          lvInfo,
          cmClimbs,
          leDone,
          "named " & $named.named & " climbs (" & $named.nothing & " with no name near)",
        )
    if p.all:
      let rows = allSectors(st)
      if rows.len == 0:
        stdout.say "no climbs found yet\n"
      else:
        for l in sectorLines(rows):
          stdout.say l & "\n"
        let hidden = countRetired(st)
        if hidden > 0:
          stdout.say noteRetired(hidden)
      return exitOk
    var ids: seq[int64]
    if p.names.len > 0:
      ids = namedClimbs(st, p.names)
      if ids.len == 0:
        return failure(
          "nch climbs", "no climb has a name like that (`nch climbs --all` lists them)"
        )
    else:
      if selectedActivities(st) == 0:
        stdout.say "nothing is selected: `nch activities CRITERIA --select` chooses activities, `nch climbs --all` lists every climb\n"
        return exitOk
      ids = selectedClimbs(st)
      if ids.len == 0:
        stdout.say "no climbs in the " & $selectedActivities(st) &
          " selected activities\n"
        return exitOk
    let colour = canColourStdout()
    for l in summaryLines(summaries(st, ids), p.everyone, p.verbose, local()):
      stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError, DownloadError:
    failure("nch climbs", getCurrentExceptionMsg())
