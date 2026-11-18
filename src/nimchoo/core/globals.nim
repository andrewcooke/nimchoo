## What every `nch` command shares: the options given before the command name, exit codes and how to report to the user.
##
## A command's `run(args): int` returns one of these.  It never raises an
## expected error (bad input, I/O trouble): it reports it on stderr, in one
## line and without a stack trace, and returns `exitFailure`.  Anything else
## that escapes is a bug and is left to crash with a trace.

import std/strutils
import ./[access, extension, fragment, theme]
import ./logfile
export logfile.Log, logfile.Level, logfile.LogEvent

{.push raises: [].}

type OutStream* = enum ## where a command's text goes
  osOut ## stdout: what was asked for
  osErr ## stderr: what is said about it (problems, progress, notes)

type Globals* = object ## Options given before the command name, for every command.
  dbPath*: string ## the database file; "" for the default
  user*: string ## whose data to work with; "" for the default user
  offline*: bool
    ## do not use the network: the names service answers "nothing" everywhere
  readOnly*: bool
    ## open the database read-only: nothing is created, nothing applied, nothing written (`openStore`, `openSession`); a
    ## database that is missing, or made by another version, is a `StoreError`.  For tab completion (`nch __complete`),
    ## which must change nothing.
  fragments*: seq[Fragment] ## the schema: the fragments of all modules
  commandNames*: seq[string]
    ## the names of all the commands (what `nch log` accepts as a filter)
  log*: Log ## the log file; nil (disabled) unless `nch` opened it
  access*: Access ## who may touch which table (`nch` fills it; nil: nothing is checked)
  extensions*: Extensions
    ## what the packages contribute to each other's extension points (`nch` fills it from the registry)
  theme*: Theme
    ## what the styles of text look like (`nch` chooses it: the `themes` package; empty: the terminal's own text)
  colour*: array[OutStream, bool]
    ## whether each stream is drawn in colour (`nch` fills it: a terminal that is not dumb, and NO_COLOR not set; in tests,
    ## neither is)

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

func inTheme*(g: Globals, o: OutStream, text: string): string =
  ## `text`, plain, as it goes to `o`: in colour, in the theme's `default` look, with the lines of a table and what is between
  ## backticks in their styles (`theme.Drawer`), and a reset at the end of each line, so that nothing runs on; so that all
  ## the text of a command looks alike.
  if not g.colour[o]:
    return text
  var d: Drawer
  let lines = text.split('\n')
  for k, line in lines:
    if k > 0:
      d.text.add '\n'
    d.draw(g.theme, baseLook(g.theme), line)
    d.endLine()
  d.text

proc file(o: OutStream): File =
  case o
  of osOut: stdout
  of osErr: stderr

proc say*(g: Globals, o: OutStream, text: string) =
  ## Write plain text to `o`, in the theme (`inTheme`).
  file(o).say g.inTheme(o, text)

proc sayRendered*(g: Globals, o: OutStream, text: string) =
  ## Write text that is already drawn (`style.render`: it has its looks) to `o`.
  file(o).say text

proc usageError*(g: Globals, command, usage, problem: string): int {.raises: [].} =
  ## Report a bad command line.
  g.say(osErr, command & ": " & problem & "\n" & usage)
  exitUsage

proc failure*(g: Globals, command, problem: string): int {.raises: [].} =
  ## Report that the work failed.
  g.say(osErr, command & ": " & problem & "\n")
  exitFailure
