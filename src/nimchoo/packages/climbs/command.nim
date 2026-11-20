## `nch climbs`: the climbs.  With no arguments the climbs selection, with the time of each and where it ranks; criteria
## (`found.nim`) or `--all` search every climb, and `--select` keeps what they find as the selection (as `nch activities`
## does); `--edit NAME` changes one (its name, or whether it is hidden); `--retired` and `--duplicates` are lists for tidying.  The climbs of the activities that have not been looked at are worked out by an
## import (`imported.nim`) and, for any still lacking, by this command, and kept (see work.nim).  The climbs are shared by all users.

import std/[options, strformat, times]
import ../../core/globals
import ../db/store
import ../user/session
import ../../core/errors
import ../../core/logfile
import ../ui/live
import ../ui/[style, vocabulary]
import ../confirm/confirm
import ../util/args/[args, usage]
import ./params
import ./attempts
import ./[chosen, found]
import ./duplicates
import ./edit
import ./naming
import ./report
import ./work
import ../ui/units

{.push raises: [].}

const commandName* = "climbs" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch climbs`, described (for tab completion).
  climbSpec().docs

const
  synopsis = """usage: nch [--db PATH] [--user NAME] climbs [-v] [--everyone]
       nch [--db PATH] [--user NAME] climbs CRITERIA|--all [--select] [-v] [--everyone]
       nch climbs --all --delete -f
       nch climbs --edit NAME --rename NEW
       nch climbs --edit NAME --auto
       nch climbs --edit NAME --retire
       nch climbs --edit NAME --unretire
       nch climbs --retired
       nch climbs --duplicates"""
  intro = @[
    ~"Show the climbs selection (with criteria, or `--all`, the climbs they find among all of them; `--select` keeps those as the selection, which `nch map climbs` and `nch calendar climbs` show too; an import selects the climbs of what it imported), each the standard way (name, category by the height gained, length, gain, gradient), then how you did on it: your best time and when, your best time on the selected rides (see `nch activities --select`; in the selection's colour) and when, where that one ranks among your own attempts, and how many times you rode it; \"manual\" marks a name given by hand.  All your attempts count in the best and the rank, not only those of the selected rides.  Times are from the bottom to the top, stops included.",
    ~"The climbs are found in the rides, once: an import works out those of every activity that has not been looked at (about a minute for two thousand rides), and keeps them; this command works out any that are still lacking.  A ride that goes over part of a climb but not all of it makes a climb of its own.",
  ]
  notes = @[
    ~"The climbs are shared by all users.  (`--user` says whose selection is used, and whose attempts are \"yours\".)"
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  usageOf(synopsis, width, intro, climbSpec().docs, notes)

func retiredText(n: int): string =
  ## Said when a list leaves out the retired climbs.
  count(n) & (if n == 1: " climb is retired" else: " climbs are retired") &
    " (hidden; `nch climbs --retired` shows them): the numbers in the names include them"

proc editClimb(g: Globals, st: Store, e: Edit): int {.raises: [StoreError].} =
  ## `--edit NAME` with one thing to change.
  let id = findShown(st, e.climb)
  let was = shownName(st, id)
  var said: Line
  case e.change.kind
  of ckRetire, ckUnretire:
    let retiring = e.change.kind == ckRetire
    setRetired(st, id, retiring)
    said =
      if retiring:
        ~"{was} is retired: hidden from the lists (`nch climbs --retired` shows it; `--unretire` brings it back)"
      else:
        ~"{was} is shown again"
  of ckAuto:
    setAuto(st, id)
    try:
      let named = nameClimbs(
        g,
        st,
        commandName,
        proc(line: string) {.closure, raises: [].} =
          g.say osErr, line & "\n"
        ,
        only = some(id),
      )
      # (what it could not do, nameClimbs has said: offline with the places not in the cache, or a damaged line)
      said =
        if named.isSome and named.get.named == 1:
          ~"{was} is now called {shownName(st, id)}"
        elif named.isSome and named.get.nothing == 1:
          ~"{was}: the name is forgotten; no place is near it (it is shown as {shownName(st, id)})"
        else:
          ~"{was}: the name is forgotten"
    except DownloadError as e:
      said = ~"{was}: the name is forgotten; {e.msg} (the next `nch climbs` names it)"
  of ckRename:
    rename(st, id, e.change.newName)
    said = ~"{was} is now called {shownName(st, id)}"
  g.log.log(lvInfo, commandName, leSaved, said.plainText)
  g.show(osOut, said)
  exitOk

proc deleteClimbs(g: Globals, st: Store, force: Force): int {.raises: [StoreError].} =
  ## `--all --delete`: every climb and the efforts on them go; the next `nch climbs` works them out again.
  let what = describe(countClimbs(st))
  if force == fNo:
    return failure(g, "nch climbs", ~"would delete {what}; use `-f` to confirm")
  pause(g.theme, what, force)
  clearClimbs(st)
  st.reclaim()
  g.log.log(lvInfo, commandName, leDeleted, fmt"deleted {what} from {st.path}")
  sayDeleted(g, fmt"deleted {what}")
  exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch climbs ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch climbs", usageText(helpWidth(stderr)), parsed.why)
  of pkOk:
    discard
  let p = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch climbs", e.msg)
  try:
    # the lists for tidying, and the changes, need no working out of climbs
    case p.action
    of caDuplicates:
      g.showAll(osOut, duplicateLines(duplicateGroups(st), helpWidth(stdout)))
      return exitOk
    of caRetired:
      let rows = allSectors(st, retired = true)
      if rows.len == 0:
        g.show(osOut, ~"no climbs are retired")
      else:
        g.showAll(osOut, sectorLines(rows, helpWidth(stdout)))
      return exitOk
    of caEdit:
      return editClimb(g, st, p.edit)
    of caDeleteAll:
      return deleteClimbs(g, st, p.force)
    of caList:
      discard
    var worked: Worked
    if canLive():
      # two lines that follow the work and stay on the screen at the end (as the import's do)
      let live = newTerminalLive(g.theme)
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
      g.done(plain(workedText(worked)))
      g.log.log(
        lvInfo,
        commandName,
        leDone,
        fmt"worked out {counted(worked.activities, ""activity"", ""activities"")}: {counted(worked.sectors, ""new climb"", ""new climbs"")}, {counted(worked.efforts, ""effort"", ""efforts"")}",
      )
    # names for the climbs that have none yet: from the places near them, fetched the first time
    discard nameClimbs(
      g,
      st,
      commandName,
      proc(line: string) {.closure, raises: [].} =
        g.say osErr, line & "\n"
      ,
    )
    let list = p.list
    var ids: seq[int64]
    case list.kind
    of lkSelection:
      ids = chosenClimbs(st)
      if ids.len == 0:
        g.tell(
          osOut,
          plain(
            "no climbs are selected: `nch climbs CRITERIA --select` chooses climbs (`nch climbs --ridden --select`: those of the selected activities), `nch climbs --all` lists every climb"
          ),
        )
        return exitOk
    of lkFound:
      let found = foundClimbs(st, list.criteria)
      for note in found.notes:
        g.say osErr, note & "\n"
      ids = found.ids
      if list.select:
        st.replaceClimbSelection(ids)
        g.log.log(lvInfo, commandName, leSaved, counted(ids.len, "climb", "climbs"))
      if not list.criteria.given:
        # (--all: every climb, and how many are hidden)
        let hidden = countRetired(st)
        if hidden > 0:
          g.warn retiredText(hidden)
      if ids.len == 0:
        let what = if list.select: " (the climbs selection is now empty)" else: ""
        g.show(osOut, ~"no climb meets the criteria{what}")
        return exitOk
    for l in summaryLines(
      summaries(st, ids),
      list.attempts.everyone,
      list.attempts.verbose,
      local(),
      helpWidth(stdout),
      marks = not g.colour[osOut],
    ):
      g.show(osOut, l)
    # (the last line, as the activities': the count in the selection's style when the climbs listed are the selection)
    let total = countLive(st)
    let isSelection = list.kind == lkSelection or list.select
    g.done(
      @[
        countSpan(ids.len, isSelection, not g.colour[osOut]),
        span(fmt" of {counted(total, ""climb"", ""climbs"")}"),
      ]
    )
    exitOk
  except StoreError, DownloadError:
    failure(g, "nch climbs", getCurrentExceptionMsg())
