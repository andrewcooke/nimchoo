## `nch import`: put the activities of FIT files into the database, and name them.  When it is done the packages that
## asked (the point `afterImport`) do their part: `selection` makes the new activities the selection.  (The module is
## not called `import` because that is a Nim keyword.)

import std/[cpuinfo, options, strutils]
import ../../core/[errors, extension, globals, logfile]
import ../db/[statement, store]
import ../download/fetch
import ../names/open
import ../ui/[live, style, vocabulary]
import ../util/args/[args, usage]
import ../user/session
import ./cmdname
export cmdname
import ./[after, batch, channel, display, events, logsink, naming, params, sinks]

const
  synopsis = "usage: nch [--db PATH] [--user NAME] import [-q] [--slow] [-j N] PATH..."
  intro =
    """Put the activities in FIT files into the database.  Each PATH is a file, or a directory that is searched
(recursively) for *.fit files.  A file whose path, size and modification time are as when it was last looked at is
skipped without being read (this includes files that could not be imported); a file that cannot be imported is
reported and the others carry on.  What happened is written to the log (see `nch log --help`).  The new activities
are then named, from the places they went through (the names are downloaded the first time they are needed).  The
activities added become your selection, ready for `nch climbs` or `nch map` (if nothing was added the selection is
left as it was)."""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(importSpec().docs, width).join("\n") & "\n"

{.push raises: [].}

const maxDefaultJobs* = 8

proc defaultJobs*(): int =
  ## The number of threads to read and decode files with: the number of processors, but not more than 8.
  min(max(1, countProcessors()), maxDefaultJobs)

proc newestActivity(st: Store): int64 {.raises: [StoreError].} =
  ## The highest activity id there is (0 if none): what is imported after it is new.
  st.db.scalar(int64, "select coalesce(max(id), 0) from activity")

proc newActivities(st: Session, after: int64): seq[int64] {.raises: [StoreError].} =
  ## The activities of this user added after the activity `after`: what this import made.
  st.db.query(
    int64,
    """select a.id from activity a join file f on f.id = a.file_id
        where a.id > :after and f.user_id = :userId order by a.id""",
    after = after,
    userId = st.userId,
  )

proc runImport(
    g: Globals, targets: seq[string], opts: ImportOptions
): int {.raises: [].} =
  ## Put the activities of the FIT files into the database, then name the ones that have no name, then do what the
  ## packages asked; returns the exit status.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch import", e.msg)
  let logged = g.log.enabled
  let screen =
    if not opts.quiet and canLive():
      liveSink(
        newTerminalLive(),
        logged,
        proc(s: string) {.closure, raises: [].} =
          stdout.say(s),
        proc(s: string) {.closure, raises: [].} =
          stderr.say(s),
      )
    else:
      plainSink(opts.quiet, logged)
  let sink =
    if g.log.enabled:
      fanOut(@[screen, logSink(g.log)])
    else:
      screen
  var before = 0'i64
  try:
    before = newestActivity(st)
  except StoreError as e:
    return failure("nch import", e.msg)
  let summary = importPaths(st, targets, opts, sink)
  # the activities without a name (these, and any from before the names existed) are named now: the names are decided
  # in the run that imports, or the command says why not
  var namingFailed = false
  try:
    let todo = pending(st).len
    if todo > 0:
      let names = openNames(
        g,
        st,
        commandName,
        proc(line: string) {.closure, raises: [].} =
          stderr.say line & "\n"
        ,
      )
      if names.isSome:
        # (a spinner while it goes on, on a terminal; the downloads it makes are said by their own lines)
        let tell = names.get.sink
        let what =
          insertSep($todo, ',') & (if todo == 1: " activity" else: " activities")
        tell(DownloadEvent(kind: deWorking, label: "naming " & what))
        var told = false
        defer:
          if not told:
            tell(DownloadEvent(kind: deWorkDone)) # (it failed: the line goes)
        let counts = ensureActivityNames(st, names.get)
        told = true
        let gps = counts.gpsErrorCount
        tell(
          DownloadEvent(
            kind: deWorkDone,
            message:
              "named " & what & ": " & $counts.named & " with a name, " &
              $counts.startOnly & " with only a start place, " & $counts.nothing &
              " with neither" &
              (if gps > 0: "; " & plural(gps, "GPS error", "GPS errors") else: ""),
          )
        )
        for e in counts.gpsErrors:
          g.log.log(
            lvWarn,
            commandName,
            leAdvisory,
            e.where & "  " & plural(e.searches, "search", "searches") &
              " for a place not made: positions too far apart (GPS errors)",
          )
        g.log.log(
          lvInfo,
          commandName,
          leDone,
          "named " & $counts.total & " activities: " & $counts.named & " with a name, " &
            $counts.startOnly & " with only a start place, " & $counts.nothing &
            " with neither" &
            (if gps > 0: "; " & plural(gps, "GPS error", "GPS errors") else: ""),
        )
  except StoreError, DownloadError:
    namingFailed = true
    discard failure(
      "nch activities",
      getCurrentExceptionMsg() &
        " (the activities are imported; they are named by the next `nch import`)",
    )
  # what the packages that asked do with the new activities (the selection is made of them)
  try:
    let ids = newActivities(st, before)
    if ids.len > 0:
      for step in g.extensions.get(afterImport):
        try:
          let said = step.run(st, ids)
          if said.isSome:
            g.log.log(lvInfo, commandName, leSaved, said.get.text)
            if not opts.quiet:
              stderr.say render(
                @[Span(text: "done: " & said.get.text, look: said.get.look)],
                canColour(),
              ) & "\n"
        except StoreError as e:
          discard failure(
            "nch import", step.failed & " (the activities are imported): " & e.msg
          )
  except StoreError as e:
    discard failure("nch import", "the new activities could not be listed: " & e.msg)
  if summary.failed > 0 or namingFailed: exitFailure else: exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch import", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  runImport(
    g,
    p.paths,
    ImportOptions(
      steps: g.extensions.get(importStep),
      quiet: p.quiet,
      slow: p.slow,
      jobs: (if p.jobs > 0: p.jobs else: defaultJobs()),
    ),
  )
