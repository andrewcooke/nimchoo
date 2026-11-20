## The live display of `nch import` (see packages/ui/live.nim): two lines that follow the
## run and are left on screen, final numbers and all, when it ends.  Nothing is
## printed per file; failures are counted here and written in the log.
##
##     importing 1,204 / 3,000   2018-08-27-rec.fit
##     imported 3 · unchanged 1,196 · failed 5 (no activity 4, bad format 1) · advisories 17
##
## `renderImport` is a pure function of the counts, so it is tested without a
## terminal; the sink only keeps the counts and asks the Live when to draw.

import std/[os, strutils]
import ../ui/live
import ../ui/style
import ../ui/vocabulary
import ../../core/globals
import ./sinks
import ./events
import ../ui/units

{.push raises: [].}

const dot = " · "

func renderImport*(sum: Summary, index: int, current: string): seq[Line] =
  ## The lines for the run so far: file number `index` (the one being looked
  ## at, `current`, if any) of `sum.total`.  What is zero is left out, except
  ## imported and failed.
  var first: Line =
    @[span("importing ", "em"), span(count(index) & " / " & count(sum.total))]
  if current.len > 0:
    first.add span("   " & current, "hide")
  var second: Line
  template part(sp: Span) =
    if second.len > 0:
      second.add span(dot, "hide")
    second.add sp

  # the styles are those of the events of the same name (packages/ui/vocabulary.nim)
  part span("imported " & count(sum.imported), leImported)
  if sum.duplicates > 0:
    part span("duplicates " & count(sum.duplicates), leDuplicate)
  if sum.unchanged > 0:
    part span("unchanged " & count(sum.unchanged), leUnchanged)
  if sum.monitor > 0:
    part span("monitor " & count(sum.monitor), leUnchanged)
  if sum.known > 0:
    part span("known failures " & count(sum.known), leUnchanged)
  if sum.failed > 0:
    part span(
      "failed " & count(sum.failed) & " (" & failureBreakdown(sum) & ")", leFailed
    )
  else:
    part span("failed 0", leUnchanged) # (nothing to see: dim)
  if sum.advisories > 0:
    part span("advisories " & count(sum.advisories), leAdvisory)
  @[first, second]

func readLine*(sum: Summary): string =
  ## The line after the display: the summary of the files read.  It does not say "done:", because what follows (the
  ## names, the selection) is not over yet.
  "read: " & summaryLine(sum)

proc liveSink*(
    l: Live,
    logged: bool,
    stdoutWrite, stderrWrite: proc(s: string) {.closure, raises: [].},
): Sink =
  ## Show the run on `l`.  When it ends the last frame stays on screen, then
  ## `stdoutWrite` gets the done line, and `stderrWrite` any notes and the hint
  ## about how to look for more (`nch log ...`, if there is a log).
  var sum = Summary()
  var index = 0
  var current = ""
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    case ev.kind
    of evStart:
      sum.total = ev.total
    of evFileStart:
      index = ev.startIndex
      current = extractFilename(ev.startPath)
    of evFileDone:
      sum.tally(ev)
      index = ev.index
    of evFinish:
      l.keep(renderImport(sum, sum.done, ""))
      stdoutWrite readLine(sum) & "\n"
      for note in ev.summary.warnings:
        stderrWrite warnLine(note).text & "\n"
      let hint = moreHint(sum, logged)
      if hint.len > 0:
        stderrWrite hint & "\n"
      return
    if l.due():
      l.show(renderImport(sum, index, current))
