## `nch import`: put the activities of FIT files into the database.
## (The command of the activity module; the module is not called `import`
## because that is a Nim keyword.)

import std/[cpuinfo, strutils]
import ../cli/[args, common]
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

type ImportArgs = object
  opts: ImportOptions
  targets: seq[string]
  help: bool

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  var given = ImportArgs(opts: ImportOptions(steps: g.importSteps))
  given.opts.jobs = min(max(1, countProcessors()), maxDefaultJobs)
  let jobsOption = custom(ImportArgs, ["-j", "--jobs"], true):
    var n = 0
    if not parseIntIn(value, 1, 256, n): return valueIs(name, "a number of threads, 1 to 256", value)
    p.opts.jobs = n
    ""
  let spec = Spec[ImportArgs](
    opts: @[flag(ImportArgs, ["-h", "--help"], help),
            custom(ImportArgs, ["-q", "--quiet"], false, (p.opts.quiet = true; "")),
            custom(ImportArgs, ["--slow"], false, (p.opts.slow = true; "")),
            jobsOption],
    positional: proc(p: var ImportArgs, arg: string): string {.nimcall, raises: [].} =
      p.targets.add arg
      "")
  let why = parseOptions(args, spec, given)
  if why.len > 0: return usageError("nch import", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  var opts = given.opts
  let targets = given.targets
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
