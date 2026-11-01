## Sinks for the events of `nch import` (events.nim): what to do with them.
## The plain sink prints the lines `nch import` has always printed; the pure
## function behind it is `plainLines`, so tests can check the text without a
## terminal.  (The live display and the log are in later modules.)

import std/[strutils, tables]
import ../commands/common
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
    lines*, warnings*: seq[string]       ## for stdout, for stderr
    imported*, skipped*, failed*, known*: int

func plural*(n: int, one, many: string): string =
  $n & " " & (if n == 1: one else: many)

func warningLines*(path: string, ws: seq[Warning]): seq[string] =
  ## One line per kind of warning in a file: the first of its kind, and how
  ## many more there were.
  var count: Table[WarningKind, int]
  for w in ws: count.mgetOrPut(w.kind, 0) += 1
  var shown: seq[WarningKind]
  for w in ws:
    if w.kind in shown: continue
    shown.add w.kind
    let more = count.getOrDefault(w.kind) - 1
    result.add "warning: " & path & ": offset " & $w.offset & ": " & w.msg &
      (if more > 0: " (and " & $more & " more like it)" else: "")

func summaryLine*(s: Summary): string =
  result = plural(s.done, "file", "files") & ": " & $s.imported &
    " imported, " & $s.skipped & " skipped, " & $s.failed & " failed"
  if s.known > 0:
    result.add ", " & plural(s.known, "known failure", "known failures") &
      " (use --slow to retry)"

func plainLines*(ev: ImportEvent, quiet: bool): Lines =
  ## The lines to print for an event.  Failures, warnings and the summary are
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
    of oAlreadyImported:
      if not quiet: result.stdout.add "skipped   " & ev.path & "  (already imported)"
    of oUnchanged:
      if not quiet: result.stdout.add "skipped   " & ev.path & "  (unchanged)"
    of oKnownFailure:
      if not quiet:
        result.stdout.add "known     " & ev.path & "  (failed before: " &
          ev.message & ")"
    of oFailed:
      result.stdout.add "failed    " & ev.path & ": " & ev.message
    result.stderr.add warningLines(ev.path, ev.warnings)
  of evFinish:
    for note in ev.summary.notes: result.stderr.add "warning: " & note
    result.stdout.add summaryLine(ev.summary)

proc plainSink*(quiet: bool): Sink =
  ## Print the plain lines as the events come.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    let lines = plainLines(ev, quiet)
    for l in lines.stdout: stdout.say l & "\n"
    for l in lines.stderr: stderr.say l & "\n"

proc reportSink*(report: Report, quiet: bool): Sink =
  ## Collect the plain lines into `report`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    let lines = plainLines(ev, quiet)
    report.lines.add lines.stdout
    report.warnings.add lines.stderr
    if ev.kind == evFinish:
      report.imported = ev.summary.imported
      report.skipped = ev.summary.skipped
      report.failed = ev.summary.failed
      report.known = ev.summary.known
