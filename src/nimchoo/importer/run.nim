## Importing: put the activities of FIT files into the database, and name them (the work of `nch activities --import`,
## whose command line is the `activities` command's; the module is not called `import` because that is a Nim keyword).

import std/[cpuinfo, options, strutils]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ../names/open
import ../ui/[live, logfile, style]
import ./[batch, display, events, logsink, naming, sinks]

{.push raises: [].}

const maxDefaultJobs* = 8

proc defaultJobs*(): int =
  ## The number of threads to read and decode files with: the number of processors, but not more than 8.
  min(max(1, countProcessors()), maxDefaultJobs)

proc newestActivity(st: Store): int64 {.raises: [StoreError].} =
  ## The highest activity id there is (0 if none): what is imported after it is new.
  guard:
    let v = st.db.getValue(sql"select coalesce(max(id), 0) from activity")
    try: result = parseBiggestInt(v)
    except ValueError: raiseStore("a bad id")

proc selectNew(st: Store, after: int64): int {.raises: [StoreError].} =
  ## Make the user's selection the activities imported after `after` (their own, in the files of this user), so that the
  ## commands that work on the selection are ready to use on the ride just imported.  Nothing new: the selection stays.
  guard:
    let n = st.db.getValue(sql"""select count(*) from activity a join file f on f.id = a.file_id
                                    where a.id > ? and f.user_id = ?""", after, st.userId)
    try: result = parseInt(n)
    except ValueError: raiseStore("a bad count")
  if result == 0: return
  st.begin()
  var done = false
  try:
    guard:
      st.db.exec(sql"delete from selection where user_id = ?", st.userId)
      st.db.exec(sql"""insert into selection(user_id, activity_id)
                       select ?, a.id from activity a join file f on f.id = a.file_id
                        where a.id > ? and f.user_id = ?""", st.userId, after, st.userId)
    st.commit()
    done = true
  finally:
    if not done: st.rollback()

proc runImport*(g: Globals, targets: seq[string], opts: ImportOptions): int {.raises: [].} =
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
      liveSink(newTerminalLive(), logged,
               proc(s: string) {.closure, raises: [].} = stdout.say(s),
               proc(s: string) {.closure, raises: [].} = stderr.say(s))
    else:
      plainSink(opts.quiet, logged)
  let sink = if g.log.enabled: fanOut(@[screen, logSink(g.log)]) else: screen
  var before = 0'i64
  try: before = newestActivity(st)
  except StoreError as e: return failure("nch activities", e.msg)
  let summary = importPaths(st, targets, opts, sink)
  # the activities without a name (these, and any from before the names existed) are named now: the names are decided
  # in the run that imports, or the command says why not
  var namingFailed = false
  try:
    if pending(st).len > 0:
      let names = openNames(g, st, "import", proc(line: string) {.closure, raises: [].} = stderr.say line & "\n")
      if names.isSome:
        let counts = ensureActivityNames(st, names.get)
        g.log.log(lvInfo, "import", leDone, "named " & $counts.total & " activities: " & $counts.named & " with a name, " &
                  $counts.startOnly & " with only a start place, " & $counts.nothing & " with neither")
  except StoreError, DownloadError:
    namingFailed = true
    discard failure("nch activities", getCurrentExceptionMsg() & " (the activities are imported; they are named by the next `nch activities --import`)")
  # the new activities become the selection
  try:
    let n = selectNew(st, before)
    if n > 0:
      g.log.log(lvInfo, "activities", leSaved, $n & (if n == 1: " activity" else: " activities") & " selected (imported)")
      if not opts.quiet:
        stderr.say render(@[span("selected " & (if n == 1: "the new activity" else: "the " & $n & " new activities"), yellow)],
                          canColour()) & "\n"
  except StoreError as e:
    discard failure("nch activities", "the new activities could not be selected: " & e.msg)
  if summary.failed > 0 or namingFailed: exitFailure else: exitOk
