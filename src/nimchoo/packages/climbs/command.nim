## `nch climbs`: the climbs.  With no arguments the climbs of the selected activities, with the time of each and where
## it ranks; `--all` every climb found; `--edit NAME` changes one (its name, or whether it is hidden); `--retired` and
## `--duplicates` are lists for tidying.  The first time (and after an import) it works out the climbs of the activities
## that have not been looked at, and keeps them (see work.nim).  The climbs are shared by all users.

import std/[options, strutils, times]
import ../../core/globals
import ../db/store
import ../user/session
import ../../core/errors
import ../names/open
import ../../core/logfile
import ../ui/live
import ../ui/style
import ../confirm/confirm
import ../util/args/[args, usage]
import ./params
import ./attempts
import ./duplicates
import ./edit
import ./naming
import ./report
import ./work

{.push raises: [].}

const commandName* = "climbs" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch climbs`, described (for tab completion).
  climbSpec().docs

const
  synopsis = """usage: nch [--db PATH] [--user NAME] climbs [-v] [--everyone]
       nch [--db PATH] [--user NAME] climbs --name TEXT... [-v] [--everyone]
       nch climbs --all
       nch climbs --all --delete -f
       nch climbs --edit NAME --rename NEW
       nch climbs --edit NAME --auto
       nch climbs --edit NAME --retire
       nch climbs --edit NAME --unretire
       nch climbs --retired
       nch climbs --duplicates"""
  intro =
    """Show the climbs the selected activities went up (see `nch activities --select`), each the standard way (name,
category by the height gained, length, gain, gradient), then how you did on it: your best time and when, your best time
on the selected rides (blue) and when, where that one ranks among your own attempts, and how many times you rode it.
All your attempts count in the best and the rank, not only those of the selected rides.  Times are from the bottom to the
top, stops included.

The climbs are found in the rides, once: the first time it works out those of every activity that has not been looked at
(about a minute for two thousand rides), and keeps them; after an import it only looks at the new ones.  A ride that goes
over part of a climb but not all of it makes a climb of its own."""
  notes =
    "The climbs are shared by all users.  (`--user` says whose selection is used, and whose attempts are \"yours\".)"

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(climbSpec().docs, width).join("\n") & "\n\n" & prose(notes, width) & "\n"

func noteRetired(count: int): string =
  $count & (if count == 1: " climb is retired" else: " climbs are retired") &
    " (hidden; `nch climbs --retired` shows them): the numbers in the names include them\n"

func damagedText(n: Named): string =
  ## What to say about climbs that were not named because their route cannot be read.
  $n.damaged.len & (if n.damaged.len == 1: " climb has" else: " climbs have") &
    " a route that cannot be read (damaged data) and " &
    (if n.damaged.len == 1: "was" else: "were") & " not named: " & n.damaged.join(", ")

proc editClimb(g: Globals, st: Store, e: Edit): int {.raises: [StoreError].} =
  ## `--edit NAME` with one thing to change.
  let id = findShown(st, e.climb)
  let was = shownName(st, id)
  var said: string
  case e.change.kind
  of ckRetire, ckUnretire:
    let retiring = e.change.kind == ckRetire
    setRetired(st, id, retiring)
    said =
      was & (
        if retiring:
        " is retired: hidden from the lists (`nch climbs --retired` shows it; --unretire brings it back)"
        else: " is shown again"
      )
  of ckAuto:
    setAuto(st, id)
    said = was & ": the name is forgotten"
    let names = openNames(
      g,
      st,
      commandName,
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
  of ckRename:
    rename(st, id, e.change.newName)
    said = was & " is now called " & shownName(st, id)
  g.log.log(lvInfo, commandName, leSaved, said)
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
  g.log.log(lvInfo, commandName, leDeleted, "deleted " & what & " from " & st.path)
  sayDeleted("deleted " & what)
  exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch climbs ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch climbs", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch climbs", e.msg)
  try:
    # the lists for tidying, and the changes, need no working out of climbs
    case p.action
    of caDuplicates:
      for l in duplicateLines(duplicateGroups(st)):
        stdout.say l & "\n"
      return exitOk
    of caRetired:
      let rows = allSectors(st, retired = true)
      if rows.len == 0:
        stdout.say "no climbs are retired\n"
      else:
        for l in sectorLines(rows):
          stdout.say l & "\n"
      return exitOk
    of caEdit:
      return editClimb(g, st, p.edit)
    of caDeleteAll:
      return deleteClimbs(g, st, p.force)
    of caAll, caNamed, caSelected:
      discard
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
        commandName,
        leDone,
        "worked out " & $worked.activities & " activities: " & $worked.sectors &
          " new climbs, " & $worked.efforts & " efforts",
      )
    # names for the climbs that have none yet: from the places near them, fetched the first time
    let names = openNames(
      g,
      st,
      commandName,
      proc(line: string) {.closure, raises: [].} =
        stderr.say line & "\n"
      ,
    )
    if names.isSome:
      let named = ensureSectorNames(st, names.get)
      if named.damaged.len > 0:
        stderr.say "warning: " & damagedText(named) & "\n"
        g.log.log(lvWarn, commandName, leAdvisory, damagedText(named))
      if named.named + named.nothing > 0:
        g.log.log(
          lvInfo,
          commandName,
          leDone,
          "named " & $named.named & " climbs (" & $named.nothing & " with no name near)",
        )
    if p.action == caAll:
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
    if p.action == caNamed:
      ids = namedClimbs(st, p.named.names)
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
    let attempts = if p.action == caNamed: p.named.attempts else: p.selected
    let colour = canColourStdout()
    for l in summaryLines(
      summaries(st, ids), attempts.everyone, attempts.verbose, local()
    ):
      stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError, DownloadError:
    failure("nch climbs", getCurrentExceptionMsg())
