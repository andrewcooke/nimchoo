## `nch import`: put the activities of FIT files into the database.
## (The command of the activity module; the module is not called `import`
## because that is a Nim keyword.)

import std/strutils
import ../commands/common
import ../db/store
import ../errors
import ../ui/live
import ./[batch, display, sinks]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] import [-q] [--slow] PATH...

Import the activities in FIT files into the database.  Each PATH is a file, or
a directory that is searched (recursively) for *.fit files.  A file whose path,
size and modification time are as when it was last looked at is skipped
without being read (this includes files that could not be imported); a file
that cannot be imported is reported and the others carry on.

  -q, --quiet   report only failures and the summary
  --slow        read and check every file, even those unchanged since last
                time (finds files that were moved or copied; retries failures)
  -h, --help    show this help
"""

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  var opts = ImportOptions()
  var targets: seq[string]
  for a in args:
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-q", "--quiet"]:
      opts.quiet = true
    elif a == "--slow":
      opts.slow = true
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
  defer: st.close()
  let sink =
    if not opts.quiet and canLive():
      liveSink(newTerminalLive(),
               proc(s: string) {.closure, raises: [].} = stdout.say(s),
               proc(s: string) {.closure, raises: [].} = stderr.say(s))
    else:
      plainSink(opts.quiet)
  let summary = importPaths(st, targets, opts, sink)
  if summary.failed > 0: exitFailure else: exitOk
