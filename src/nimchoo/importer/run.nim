## Importing: put the activities of FIT files into the database, and name them (the work of `nch activities --import`,
## whose command line is the `activities` command's; the module is not called `import` because that is a Nim keyword).

import std/[cpuinfo, options, strutils]
import ../cli/catalog
import ../core/globals
import ../db/[statement, store]
import ../download/fetch
import ../core/errors
import ../names/open
import ../core/logfile
import ../packages/ui/live
import ../packages/ui/style
import ./[batch, display, events, logsink, naming, sinks]

{.push raises: [].}

const maxDefaultJobs* = 8

proc defaultJobs*(): int =
  ## The number of threads to read and decode files with: the number of processors, but not more than 8.
  min(max(1, countProcessors()), maxDefaultJobs)

proc newestActivity(st: Store): int64 {.raises: [StoreError].} =
  ## The highest activity id there is (0 if none): what is imported after it is new.
  st.db.scalar(int64, "select coalesce(max(id), 0) from activity")

proc selectNew(st: Store, after: int64): int {.raises: [StoreError].} =
  ## Make the user's selection the activities imported after `after` (their own, in the files of this user), so that the
  ## commands that work on the selection are ready to use on the ride just imported.  Nothing new: the selection stays.
  result = st.db.scalar(
    int,
    """select count(*) from activity a join file f on f.id = a.file_id
                                    where a.id > :id and f.user_id = :userId""",
    id = after,
    userId = st.userId,
  )
  if result == 0:
    return
  st.begin()
  var done = false
  try:
    st.db.execute("delete from selection where user_id = :userId", userId = st.userId)
    st.db.execute(
      """insert into selection(user_id, activity_id)
                       select :userId, a.id from activity a join file f on f.id = a.file_id
                        where a.id > :after and f.user_id = :userId""",
      userId = st.userId,
      after = after,
    )
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

proc runImport*(
    g: Globals, targets: seq[string], opts: ImportOptions
): int {.raises: [].} =
  ## `nch activities --import PATH...`: put the activities of the FIT files into the database, then name the ones that
  ## have no name; returns the exit status.
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch activities", e.msg)
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
    return failure("nch activities", e.msg)
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
        cmActivities,
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
            $cmActivities,
            leAdvisory,
            e.where & "  " & plural(e.searches, "search", "searches") &
              " for a place not made: positions too far apart (GPS errors)",
          )
        g.log.log(
          lvInfo,
          $cmActivities,
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
        " (the activities are imported; they are named by the next `nch activities --import`)",
    )
  # the new activities become the selection
  try:
    let n = selectNew(st, before)
    if n > 0:
      g.log.log(
        lvInfo,
        $cmActivities,
        leSaved,
        $n & (if n == 1: " activity" else: " activities") & " selected (imported)",
      )
      if not opts.quiet:
        stderr.say render(
          @[
            span(
              "done: selected " &
                (if n == 1: "the new activity"
                else: "the " & $n & " new activities"),
              blue,
            )
          ],
          canColour(),
        ) & "\n"
  except StoreError as e:
    discard
      failure("nch activities", "the new activities could not be selected: " & e.msg)
  if summary.failed > 0 or namingFailed: exitFailure else: exitOk
