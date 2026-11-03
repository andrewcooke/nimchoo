## Reading the log: lines of the current format
##
##     2026-11-02T23:10:34Z INFO  import    duplicate  text
##
## taken apart (the event word is found, for colouring), filtered by command and
## event, cut to the latest run, and styled with the look of each event
## (ui/vocabulary.nim).  Lines of other shapes (from older versions) are kept
## but match no filter.  Pure: no files, no terminal.

import std/[options, strutils]
import ../ui/[style, vocabulary]

{.push raises: [].}

type
  LogLine* = object
    raw*: string
    command*: string                 ## "" if the line is not in the current format
    event*: Option[LogEvent]         ## none if not
    eventStart*, eventEnd*: int      ## where the event word is in `raw`

  Filter* = object
    commands*: seq[string]           ## only these commands (none: any)
    events*: set[LogEvent]           ## only these events (empty: any)
    last*: bool                      ## only the latest run (see `select` below)
    count*: int                      ## only the last N lines (0: all)

  Selected* = object
    lines*: seq[LogLine]
    noRun*: bool                     ## `last` was asked for, but there is no run to show

func isLevel(s: string): bool = s in ["INFO", "WARN", "ERROR"]

func parseLine*(raw: string): LogLine =
  ## Take a line apart: time, level, command, event, then the text.
  result = LogLine(raw: raw)
  var tokens: seq[tuple[word: string, start, stop: int]]
  var i = 0
  while i < raw.len and tokens.len < 4:
    while i < raw.len and raw[i] == ' ': inc i
    let start = i
    while i < raw.len and raw[i] != ' ': inc i
    if i > start: tokens.add (raw[start ..< i], start, i)
  if tokens.len < 4: return
  if not (tokens[0].word.len == 20 and tokens[0].word.endsWith("Z") and isLevel(tokens[1].word)):
    return
  let e = parseEvent(tokens[3].word)
  if e.isNone: return
  result.command = tokens[2].word
  result.event = e
  result.eventStart = tokens[3].start
  result.eventEnd = tokens[3].stop

func matches(l: LogLine, f: Filter): bool =
  if f.commands.len > 0 and l.command notin f.commands: return false
  if f.events != {} and (l.event.isNone or l.event.get notin f.events): return false
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
      if l.event == some(leRun) and (f.commands.len == 0 or l.command in f.commands):
        start = i
        found = true
        break
    if not found: return Selected(noRun: true)
  for i in start .. lines.high:
    if lines[i].matches(f): result.lines.add lines[i]
  if f.count > 0 and result.lines.len > f.count:
    result.lines = result.lines[result.lines.len - f.count .. ^1]

func styled*(l: LogLine): Line =
  ## The line, with the event word in the look of the event.
  if l.event.isNone: return plain(l.raw)
  @[span(l.raw[0 ..< l.eventStart]),
    span(l.raw[l.eventStart ..< l.eventEnd], l.event.get),
    span(l.raw[l.eventEnd .. ^1])]
