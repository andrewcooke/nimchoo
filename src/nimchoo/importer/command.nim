## `nch import`: put the activities of FIT files into the database.
## (The command of the activity module; the module is not called `import`
## because that is a Nim keyword.)

import std/[cpuinfo, strutils]
import ../cli/common
import ../db/store
import ../errors
import ../ui/[live, logfile]
import ./[batch, display, events, logsink, sinks]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] import [-q] [--slow] [-j N] PATH...

Import the activities in FIT files into the database.  Each PATH is a file, or
a directory that is searched (recursively) for *.fit files.  A file whose path,
size and modification time are as when it was last looked at is skipped
without being read (this includes files that could not be imported); a file
that cannot be imported is reported and the others carry on.  What happened is
written to the log; see `nch log --help`.

  -q, --quiet   report only failures and the summary
  --slow        read and check every file, even those unchanged since last
                time (finds files that were moved or copied; retries failures)
  -j, --jobs N  use N threads to read and decode the files (the database is written by one
                thread, in the order of the files, so the result is the same); 1: no
                threads.  Default: the number of processors, but not more than 8
  -h, --help    show this help
"""

const maxDefaultJobs = 8

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  var opts = ImportOptions(steps: g.importSteps)
  var targets: seq[string]
  opts.jobs = min(max(1, countProcessors()), maxDefaultJobs)
  var i = 0
  while i < args.len:
    let a = args[i]
    inc i
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-q", "--quiet"]:
      opts.quiet = true
    elif a == "--slow":
      opts.slow = true
    elif a in ["-j", "--jobs"]:
      if i >= args.len: return usageError("nch import", usage, a & " needs a number")
      try:
        opts.jobs = parseInt(args[i])
      except ValueError:
        opts.jobs = 0
      if opts.jobs < 1 or opts.jobs > 256:
        return usageError("nch import", usage, a & " is a number of threads, 1 to 256 (not '" & args[i] & "')")
      inc i
    elif a.startsWith("-") and a != "-":
      return usageError("nch import", usage, "unknown option " & a)
    else:
      targets.add a
  if targets.len == 0:
    return usageError("nch import", usage, "expected at least one PATH")
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch import", e.msg)
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
  if summary.failed > 0: exitFailure else: exitOk
