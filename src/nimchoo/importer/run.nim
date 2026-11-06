## Importing: put the activities of FIT files into the database, and name them (the work of `nch activities --import`,
## whose command line is the `activities` command's; the module is not called `import` because that is a Nim keyword).

import std/[cpuinfo, options]
import ../cli/common
import ../db/store
import ../errors
import ../names/open
import ../ui/[live, logfile]
import ./[batch, display, events, logsink, naming, sinks]

{.push raises: [].}

const maxDefaultJobs* = 8

proc defaultJobs*(): int =
  ## The number of threads to read and decode files with: the number of processors, but not more than 8.
  min(max(1, countProcessors()), maxDefaultJobs)

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
  if summary.failed > 0 or namingFailed: exitFailure else: exitOk
