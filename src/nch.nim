## nch: the nimchoo command line tool.  A thin dispatcher: each command lives
## in its own module under nimchoo/commands/ and exposes `run(args): int`.
## Options common to all commands (database connections etc) are to be parsed
## here, before the command name.

import std/os
import nimchoo/commands/fit

const usage = """usage: nch COMMAND [ARGS]

commands:
  fit    read FIT files (see `nch fit --help`)
"""

proc main(): int =
  let args = commandLineParams()
  if args.len == 0:
    stderr.write usage
    return 2
  case args[0]
  of "-h", "--help", "help":
    stdout.write usage
    0
  of "fit":
    fit.run(args[1 .. ^1])
  else:
    stderr.write "nch: unknown command " & args[0] & "\n" & usage
    2

when isMainModule:
  quit main()
