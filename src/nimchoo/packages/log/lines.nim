## Reading the log: lines of the current format
##
##     2026-11-02T23:10:34Z INFO  import    duplicate  text
##
## taken apart (the event word is found, for colouring), filtered by command and
## event, cut to the latest run, and styled with the look of each event
## (packages/ui/vocabulary.nim).  Lines of other shapes (from older versions) are kept
## but match no filter.  Pure: no files, no terminal.

import std/[options, strutils]
import ../ui/style
import ../../core/markup
import ../../core/logfile
import ../ui/vocabulary

{.push raises: [].}

type
  LogLine* = object
    raw*: string
    fields*: Option[LogFields] ## none if the line is not in the current format

  Filter* = object
    commands*: seq[string] ## only these commands (none: any)
    events*: set[LogEvent] ## only these events (empty: any)
    last*: bool ## only the latest run (see `select` below)
    count*: Option[int] ## only the last N lines (none: all)

  Selected* = object
    lines*: seq[LogLine]
    noRun*: bool ## `last` was asked for, but there is no run to show

func parseLine*(raw: string): LogLine =
  ## Take a line apart (`core/logfile.parseLogLine`, which reads what the writer writes).
  LogLine(raw: raw, fields: parseLogLine(raw))

func matches(l: LogLine, f: Filter): bool =
  if f.commands.len > 0 and (l.fields.isNone or l.fields.get.command notin f.commands):
    return false
  if f.events != {} and (l.fields.isNone or l.fields.get.event notin f.events):
    return false
  true

func select*(lines: seq[LogLine], f: Filter): Selected =
  ## The lines to show.  `last`: start from the latest `run` line of one of the
  ## commands (of any command if none is given) and show what follows it.  Then
  ## the filters, then the last `count` lines.
  var start = 0
  if f.last:
    var found = false
    for i in countdown(lines.high, 0):
      let l = lines[i]
      if l.fields.isSome and l.fields.get.event == leRun and
          (f.commands.len == 0 or l.fields.get.command in f.commands):
        start = i
        found = true
        break
    if not found:
      return Selected(noRun: true)
  for i in start .. lines.high:
    if lines[i].matches(f):
      result.lines.add lines[i]
  if f.count.isSome and result.lines.len > f.count.get:
    result.lines = result.lines[result.lines.len - f.count.get .. ^1]

func levelStyle*(level: string): StyleName =
  ## ERROR bad, WARN a warning, INFO hidden: the quiet ordinary lines, and the ones that need a look.
  case level
  of "ERROR":
    styleName"bad"
  of "WARN":
    styleName"warn"
  else:
    styleName"hide"

func styled*(l: LogLine): Line =
  ## The line, with the level word in its style (bad ERROR, warning WARN, hidden INFO) and the event word in the style of
  ## the event.
  if l.fields.isNone:
    return plain(l.raw)
  let f = l.fields.get
  let level = levelStyle(l.raw[f.levelStart ..< f.levelEnd])
  ~"{l.raw[0 ..< f.levelStart]}<{level} {l.raw[f.levelStart ..< f.levelEnd]}>{l.raw[f.levelEnd ..< f.eventStart]}<{f.event} {l.raw[f.eventStart ..< f.eventEnd]}>{l.raw[f.eventEnd .. ^1]}"
