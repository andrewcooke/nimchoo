## What every `nch` command shares: the options given before the command name, exit codes and how to report to the user.
##
## A command's `run(args): int` returns one of these.  It never raises an
## expected error (bad input, I/O trouble): it reports it on stderr, in one
## line and without a stack trace, and returns `exitFailure`.  Anything else
## that escapes is a bug and is left to crash with a trace.

import ./[access, extension, fragment]
import ./logfile
export logfile.Log, logfile.Level, logfile.LogEvent

{.push raises: [].}

type Globals* = object ## Options given before the command name, for every command.
  dbPath*: string ## the database file; "" for the default
  user*: string ## whose data to work with; "" for the default user
  offline*: bool
    ## do not use the network: the names service answers "nothing" everywhere
  fragments*: seq[Fragment] ## the schema: the fragments of all modules
  commandNames*: seq[string]
    ## the names of all the commands (what `nch log` accepts as a filter)
  log*: Log ## the log file; nil (disabled) unless `nch` opened it
  access*: Access ## who may touch which table (`nch` fills it; nil: nothing is checked)
  extensions*: Extensions
    ## what the packages contribute to each other's extension points (`nch` fills it from the registry)

const
  exitOk* = 0
  exitFailure* = 1 ## the work failed (unusable input, I/O error)
  exitUsage* = 2 ## the command line was wrong

proc say*(f: File, text: string) {.raises: [].} =
  ## Write to a standard stream.  If even that fails there is nothing more
  ## that can be done about it.
  try:
    f.write text
  except IOError:
    discard

proc usageError*(command, usage, problem: string): int {.raises: [].} =
  ## Report a bad command line.
  stderr.say command & ": " & problem & "\n" & usage
  exitUsage

proc failure*(command, problem: string): int {.raises: [].} =
  ## Report that the work failed.
  stderr.say command & ": " & problem & "\n"
  exitFailure
