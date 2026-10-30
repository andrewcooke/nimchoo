## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/commands/ and exposes `run(args): int` (see
## commands/common.nim for the exit codes).  Options common to all commands
## (database connections etc) are to be parsed here, before the command name.

import std/os
import nimchoo/commands/common
import nimchoo/commands/fit

const usage = """usage: nch COMMAND [ARGS]

commands:
  fit    read FIT files (see `nch fit --help`)
"""

proc main(): int {.raises: [].} =
  let args = commandLineParams()
  if args.len == 0:
    stderr.say usage
    return exitUsage
  case args[0]
  of "-h", "--help", "help":
    stdout.say usage
    exitOk
  of "fit":
    fit.run(args[1 .. ^1])
  else:
    usageError("nch", usage, "unknown command " & args[0])

when isMainModule:
  quit main()
