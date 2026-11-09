## What every `nch` command shares: exit codes and how to report to the user.
##
## A command's `run(args): int` returns one of these.  It never raises an
## expected error (bad input, I/O trouble): it reports it on stderr, in one
## line and without a stack trace, and returns `exitFailure`.  Anything else
## that escapes is a bug and is left to crash with a trace.

import ../db/[channel, store]
import ../core/errors
import ../core/logfile
import ./catalog
export catalog, logfile.Log, logfile.Level, logfile.LogEvent

{.push raises: [].}

type Globals* = object ## Options given before the command name, for every command.
  dbPath*: string ## the database file; "" for the default
  user*: string ## whose data to work with; "" for the default user
  offline*: bool
    ## do not use the network: the names service answers "nothing" everywhere
  fragments*: seq[Fragment] ## the schema: the fragments of all modules
  importSteps*: seq[ImportStep] ## what modules add to an import
  log*: Log ## the log file; nil (disabled) unless `nch` opened it

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

proc openStore*(g: Globals): Store {.raises: [StoreError].} =
  ## The database the global options point at (see db/store.nim).
  openStore(resolveDbPath(g.dbPath), g.fragments, g.user)
