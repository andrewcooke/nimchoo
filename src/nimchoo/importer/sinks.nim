## Sinks for the events of `nch activities --import` (events.nim): what to do with them.
## The plain sink prints the lines `nch activities --import` prints when its output is not a
## terminal; the pure function behind it is `plainLines`, so tests can check the
## text without a terminal.  (The live display and the log are in other modules.)
##
## The words are the same everywhere (screen, log, hints): `imported`,
## `duplicate` (the same content was imported before), `unchanged` (the file is
## as when last looked at), `known failure`, `failed`, and `advisory` (something
## noticed in a file that was imported anyway).

import std/[strutils, tables]
import ../cli/common
import ../warnings
import ./events
import ../ui/vocabulary
import ./failure

{.push raises: [].}

type Lines* = object ## What one event prints.
  stdout*, stderr*: seq[string]

func extrasText*(c: Counts): string =
  ## ", 2,099 heart-rate readings" for what import steps wrote (nothing if they wrote none).
  for x in c.extras:
    if x.n > 0:
      result.add ", " & $x.n & " " & (if x.n == 1: x.one else: x.many)

func plural*(n: int, one, many: string): string =
  ## "1 file", "3 files".
  $n & " " & (if n == 1: one else: many)

func advisoryLines*(path: string, ws: seq[Warning]): seq[string] =
  ## One line per kind of advisory in a file: the first of its kind, and how
  ## many more there were.
  var count: Table[WarningKind, int]
  for w in ws:
    count.mgetOrPut(w.kind, 0) += 1
  var shown: seq[WarningKind]
  for w in ws:
    if w.kind in shown:
      continue
    shown.add w.kind
    let more = count.getOrDefault(w.kind) - 1
    result.add "advisory: " & path & ": offset " & $w.offset & ": " & w.msg &
      (if more > 0: " (and " & $more & " more like it)" else: "")

func failureBreakdown*(s: Summary): string =
  ## "no activity 4, bad format 1": the failures by kind ("" if none).
  var parts: seq[string]
  for k in FailureKind:
    if k != fkMonitor and s.failures[k] > 0:
      parts.add k.label & " " & $s.failures[k]
  parts.join(", ")

func summaryLine*(s: Summary): string =
  ## "1113 files, 1112 imported, 1 duplicate, 0 failed, 85 advisories": what is
  ## zero is left out, except imported and failed.
  result = plural(s.done, "file", "files") & ", " & $s.imported & " imported"
  if s.duplicates > 0:
    result.add ", " & plural(s.duplicates, "duplicate", "duplicates")
  if s.unchanged > 0:
    result.add ", " & $s.unchanged & " unchanged"
  if s.monitor > 0:
    result.add ", " & $s.monitor & " monitor"
  result.add ", " & $s.failed & " failed"
  let kinds = failureBreakdown(s)
  if kinds.len > 0:
    result.add " (" & kinds & ")"
  if s.known > 0:
    result.add ", " & plural(s.known, "known failure", "known failures") &
      " (use --slow to retry)"
  if s.advisories > 0:
    result.add ", " & plural(s.advisories, "advisory", "advisories")

func moreHint*(s: Summary, logged: bool): string =
  ## How to see more: `nch log` with the words of what happened, such as
  ## "more: nch log activities failed duplicate --last" (the latest import only).  ""
  ## if there is nothing to look into or no log.
  if not logged:
    return ""
  var words: seq[string]
  if s.failed > 0:
    words.add $leFailed
  if s.duplicates > 0:
    words.add $leDuplicate
  if s.advisories > 0:
    words.add $leAdvisory
  if words.len == 0:
    return ""
  "more: nch log activities " & words.join(" ") & " --last"

func plainLines*(ev: ImportEvent, quiet: bool, logged = false): Lines =
  ## The lines to print for an event.  Failures, advisories and the summary are
  ## always printed; the line for each file that went well is not if `quiet`.
  case ev.kind
  of evStart, evFileStart:
    discard
  of evFileDone:
    case ev.outcome
    of oImported:
      if not quiet:
        result.stdout.add "imported  " & ev.path & "  (" &
          plural(ev.counts.activities, "activity", "activities") & ", " &
          plural(ev.counts.segments, "segment", "segments") & ", " &
          plural(ev.counts.coords, "coordinate", "coordinates") & extrasText(ev.counts) &
          ")"
    of oDuplicate:
      if not quiet:
        result.stdout.add "duplicate " & ev.path & "  (" & (
          if ev.sameAs.len > 0: "same content as " & ev.sameAs
          else: "already imported"
        ) & ")"
    of oUnchanged:
      if not quiet:
        result.stdout.add "unchanged " & ev.path
    of oKnownFailure:
      if not quiet:
        result.stdout.add "known     " & ev.path & "  (failed before: " & ev.message &
          ")"
    of oMonitor:
      discard
    # (expected, and there may be thousands: only counted)
    of oFailed:
      result.stdout.add "failed    " & ev.path & ": " & ev.message
    result.stderr.add advisoryLines(ev.path, ev.advisories)
  of evFinish:
    for note in ev.summary.notes:
      result.stderr.add "note: " & note
    result.stdout.add "read: " & summaryLine(ev.summary)
    let hint = moreHint(ev.summary, logged)
    if hint.len > 0:
      result.stderr.add hint

proc plainSink*(quiet: bool, logged = false): Sink =
  ## Print the plain lines as the events come.  `logged`: there is a log, so the
  ## hint at the end can say how to look in it.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    let lines = plainLines(ev, quiet, logged)
    for l in lines.stdout:
      stdout.say l & "\n"
    if lines.stdout.len > 0 and lines.stderr.len > 0:
      try:
        stdout.flushFile()
      # (so the two streams stay in order in a pipe)
      except IOError:
        discard
    for l in lines.stderr:
      stderr.say l & "\n"
