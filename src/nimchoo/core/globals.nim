## What every `nch` command shares: the options given before the command name, exit codes and how to report to the user.
##
## A command's `run(args): int` returns one of these.  It never raises an
## expected error (bad input, I/O trouble): it reports it on stderr, in one
## line and without a stack trace, and returns `exitFailure`.  Anything else
## that escapes is a bug and is left to crash with a trace.

import std/strutils
import ./[access, extension, fragment, line, theme]
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
  width*: array[OutStream, int]
    ## how wide a message may be on each stream, to wrap it (`tell`; `nch` fills it: `ui/live.helpWidth()`); 0: no wrap
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

func paintOf*(g: Globals, o: OutStream): Paint =
  ## How lines are drawn on `o`: in the theme in force, in colour if `o` is.
  Paint(theme: g.theme, colour: g.colour[o])

proc show*(g: Globals, o: OutStream, line: Line) =
  ## Write a styled line to `o`, drawn as `o` is.
  file(o).say render(line, paintOf(g, o)) & "\n"

proc showAll*(g: Globals, o: OutStream, lines: seq[Line]) =
  ## Write styled lines to `o` (a usage, a table), drawn as `o` is.
  for l in lines:
    g.show(o, l)

proc tell*(g: Globals, o: OutStream, line: Line) =
  ## Write a message to `o`, wrapped to its width (`width`), drawn as `o` is.
  if g.width[o] > 0:
    g.showAll(o, line.wrapped(g.width[o]))
  else:
    g.show(o, line)

func oneLine*(text: string): string =
  ## A message on one line: the lines of a message from below (an `OSError` has "Additional info: ..." on a line of its
  ## own) joined with "; ".
  var parts: seq[string]
  for l in text.splitLines:
    if l.strip.len > 0:
      parts.add l.strip
  parts.join("; ")

func oneLine*(line: Line): Line =
  ## A message on one line, as for a string: where a span's text has newlines (a value, a path), its lines are joined with
  ## "; ", blank ones left out.
  for sp in line:
    if '\n' in sp.text:
      result.add Span(text: oneLine(sp.text), styles: sp.styles)
    else:
      result.add sp

proc usageError*(
    g: Globals, command: string, usage: seq[Line], problem: Line
): int {.raises: [].} =
  ## Report a bad command line: the problem (in `bad`, on one line, its literal text with backticks), then the usage.
  g.tell(osErr, within(oneLine(@[span(command & ": ")] & problem), styleName"bad"))
  g.showAll(osErr, usage)
  exitUsage

proc usageError*(
    g: Globals, command: string, usage: seq[Line], problem: string
): int {.raises: [].} =
  ## As above, with the problem as text.
  usageError(g, command, usage, plain(problem))

func warnLine*(problem: Line): Line =
  ## A warning ("warning: ..."): something advisory, the work done all the same; all in `warn`, on one line.
  within(oneLine(@[span("warning: ")] & problem), styleName"warn")

func warnLine*(text: string): Line =
  ## As above, from text.
  warnLine(plain(text))

func doneLine*(what: Line): Line =
  ## The line that says what was done ("done: 11 of 1,113 activities"): plain, with what it counts in the style that says
  ## what it is (`select`, `good`, `bad`).
  @[span("done: ")] & what

proc warn*(g: Globals, problem: Line) =
  ## Say a warning on stderr (`warnLine`), wrapped to the width.
  g.tell(osErr, warnLine(problem))

proc warn*(g: Globals, text: string) =
  ## As above, from text.
  g.warn plain(text)

proc done*(g: Globals, what: Line) =
  ## Say what was done on stdout (`doneLine`), wrapped to the width.
  g.tell(osOut, doneLine(what))

proc failure*(g: Globals, command: string, problem: Line): int {.raises: [].} =
  ## Report that the work failed: one message, on one line (wrapped to the width), all in `bad`, its literal text with
  ## backticks.
  g.tell(osErr, within(oneLine(@[span(command & ": ")] & problem), styleName"bad"))
  exitFailure

proc failure*(g: Globals, command, problem: string): int {.raises: [].} =
  ## As above, with the problem as text.
  failure(g, command, plain(problem))
