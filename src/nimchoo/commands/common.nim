## What every `nch` command shares: exit codes and how to report to the user.
##
## A command's `run(args): int` returns one of these.  It never raises an
## expected error (bad input, I/O trouble): it reports it on stderr, in one
## line and without a stack trace, and returns `exitFailure`.  Anything else
## that escapes is a bug and is left to crash with a trace.

const
  exitOk* = 0
  exitFailure* = 1  ## the work failed (unusable input, I/O error)
  exitUsage* = 2    ## the command line was wrong

proc say*(f: File, text: string) {.raises: [].} =
  ## Write to a standard stream.  If even that fails there is nothing more
  ## that can be done about it.
  try: f.write text
  except IOError: discard

proc usageError*(command, usage, problem: string): int {.raises: [].} =
  ## Report a bad command line.
  stderr.say command & ": " & problem & "\n" & usage
  exitUsage

proc failure*(command, problem: string): int {.raises: [].} =
  ## Report that the work failed.
  stderr.say command & ": " & problem & "\n"
  exitFailure
