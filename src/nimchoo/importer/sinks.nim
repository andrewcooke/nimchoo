## Sinks for the events of `nch import` (events.nim): what to do with them.
## The plain sink prints the lines `nch import` prints when its output is not a
## terminal; the pure function behind it is `plainLines`, so tests can check the
## text without a terminal.  (The live display and the log are in other modules.)
##
## The words are the same everywhere (screen, log, hints): `imported`,
## `duplicate` (the same content was imported before), `unchanged` (the file is
## as when last looked at), `known failure`, `failed`, and `advisory` (something
## noticed in a file that was imported anyway).

import std/[sequtils, strutils, tables]
import ../cli/common
import ../warnings
import ./events
import ./failure

{.push raises: [].}

type
  Lines* = object
    ## What one event prints.
    stdout*, stderr*: seq[string]

  Report* = ref object
    ## The plain output of a whole run, collected instead of printed.
    lines*, stderr*: seq[string]
    imported*, duplicates*, unchanged*, failed*, known*, advisories*: int

func plural*(n: int, one, many: string): string =
  $n & " " & (if n == 1: one else: many)

func advisoryLines*(path: string, ws: seq[Warning]): seq[string] =
  ## One line per kind of advisory in a file: the first of its kind, and how
  ## many more there were.
  var count: Table[WarningKind, int]
  for w in ws: count.mgetOrPut(w.kind, 0) += 1
  var shown: seq[WarningKind]
  for w in ws:
    if w.kind in shown: continue
    shown.add w.kind
    let more = count.getOrDefault(w.kind) - 1
    result.add "advisory: " & path & ": offset " & $w.offset & ": " & w.msg &
      (if more > 0: " (and " & $more & " more like it)" else: "")

func failureBreakdown*(s: Summary): string =
  ## "no activity 4, bad format 1": the failures by kind ("" if none).
  var parts: seq[string]
  for k in FailureKind:
    if s.failures[k] > 0: parts.add k.label & " " & $s.failures[k]
  parts.join(", ")

func summaryLine*(s: Summary): string =
  ## "1113 files: 1112 imported, 1 duplicate, 0 failed, 85 advisories": what is
  ## zero is left out, except imported and failed.
  result = plural(s.done, "file", "files") & ": " & $s.imported & " imported"
  if s.duplicates > 0: result.add ", " & plural(s.duplicates, "duplicate", "duplicates")
  if s.unchanged > 0: result.add ", " & $s.unchanged & " unchanged"
  result.add ", " & $s.failed & " failed"
  let kinds = failureBreakdown(s)
  if kinds.len > 0: result.add " (" & kinds & ")"
  if s.known > 0:
    result.add ", " & plural(s.known, "known failure", "known failures") &
      " (use --slow to retry)"
  if s.advisories > 0: result.add ", " & plural(s.advisories, "advisory", "advisories")

func shellWord(path: string): string =
  ## `path` as one word for a shell: as it is if that is safe, else in quotes.
  if path.len > 0 and path.allIt(it in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '/', '.', '_', '-', '~', '+', ','}):
    path
  else:
    "'" & path.replace("'", "'\\''") & "'"

func displayPath*(path, home: string): string =
  ## `path` with the home directory written as ~, for telling people.
  if home.len > 1 and path.startsWith(home & "/"): "~" & path[home.len .. ^1] else: path

func moreHint*(s: Summary, logPath: string): string =
  ## How to see more: a grep of the log for the words of what happened, such as
  ## "more: grep -wE 'failed|duplicate' ~/.local/state/nch/nch.log".  "" if there is
  ## nothing to look into or no log.
  if logPath.len == 0: return ""
  var words: seq[string]
  if s.failed > 0: words.add "failed"
  if s.duplicates > 0: words.add "duplicate"
  if s.advisories > 0: words.add "advisory"
  if words.len == 0: return ""
  let file = shellWord(logPath)
  if words.len == 1: "more: grep -w " & words[0] & " " & file
  else: "more: grep -wE '" & words.join("|") & "' " & file

func plainLines*(ev: ImportEvent, quiet: bool, logPath = ""): Lines =
  ## The lines to print for an event.  Failures, advisories and the summary are
  ## always printed; the line for each file that went well is not if `quiet`.
  case ev.kind
  of evStart, evFileStart: discard
  of evFileDone:
    case ev.outcome
    of oImported:
      if not quiet:
        result.stdout.add "imported  " & ev.path & "  (" &
          plural(ev.counts.activities, "activity", "activities") & ", " &
          plural(ev.counts.segments, "segment", "segments") & ", " &
          plural(ev.counts.coords, "coordinate", "coordinates") & ")"
    of oDuplicate:
      if not quiet:
        result.stdout.add "duplicate " & ev.path & "  (" &
          (if ev.sameAs.len > 0: "same content as " & ev.sameAs
           else: "already imported") & ")"
    of oUnchanged:
      if not quiet: result.stdout.add "unchanged " & ev.path
    of oKnownFailure:
      if not quiet:
        result.stdout.add "known     " & ev.path & "  (failed before: " &
          ev.message & ")"
    of oFailed:
      result.stdout.add "failed    " & ev.path & ": " & ev.message
    result.stderr.add advisoryLines(ev.path, ev.advisories)
  of evFinish:
    for note in ev.summary.notes: result.stderr.add "note: " & note
    result.stdout.add summaryLine(ev.summary)
    let hint = moreHint(ev.summary, logPath)
    if hint.len > 0: result.stderr.add hint

proc plainSink*(quiet: bool, logPath = ""): Sink =
  ## Print the plain lines as the events come.  `logPath` ("" if there is no
  ## log) is where the hint at the end says to look.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    let lines = plainLines(ev, quiet, logPath)
    for l in lines.stdout: stdout.say l & "\n"
    if lines.stdout.len > 0 and lines.stderr.len > 0:
      try: stdout.flushFile()          # (so the two streams stay in order in a pipe)
      except IOError: discard
    for l in lines.stderr: stderr.say l & "\n"

proc reportSink*(report: Report, quiet: bool): Sink =
  ## Collect the plain lines into `report`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    let lines = plainLines(ev, quiet)
    report.lines.add lines.stdout
    report.stderr.add lines.stderr
    if ev.kind == evFinish:
      report.imported = ev.summary.imported
      report.duplicates = ev.summary.duplicates
      report.unchanged = ev.summary.unchanged
      report.failed = ev.summary.failed
      report.known = ev.summary.known
      report.advisories = ev.summary.advisories
