## The live display of `nch import` (see ui/live.nim): two lines that follow the
## run, and permanent lines above them for each failure.
##
##     importing 1,204 / 3,000   2018-08-27-rec.fit
##     imported 3 · skipped 1,196 · failed 5 (no activity 4, bad format 1) · warnings 17
##
## `renderImport` is a pure function of the counts, so it is tested without a
## terminal; the sink only keeps the counts and asks the Live when to draw.

import std/[os, strutils]
import ../ui/[live, style]
import ./[events, sinks]

{.push raises: [].}

const dot = " · "

func commas(n: int): string = insertSep($n, ',')

func renderImport*(sum: Summary, index: int, current: string): seq[Line] =
  ## The lines for the run so far: file number `index` (the one being looked
  ## at, `current`) of `sum.total`.
  var first: Line = @[span("importing ", bold = true),
                      span(commas(index) & " / " & commas(sum.total)),
                      span("   " & current, dim = true)]
  var second: Line
  second.add span("imported " & commas(sum.imported),
                  if sum.imported > 0: cGreen else: cNone)
  second.add span(dot, dim = true)
  second.add span("skipped " & commas(sum.skipped + sum.known), dim = true)
  second.add span(dot, dim = true)
  if sum.failed > 0:
    second.add span("failed " & commas(sum.failed) & " (" &
                    failureBreakdown(sum) & ")", cRed, bold = true)
  else:
    second.add span("failed 0", dim = true)
  if sum.warnings > 0:
    second.add span(dot, dim = true)
    second.add span("warnings " & commas(sum.warnings), cYellow)
  @[first, second]

func failureLine*(path, message: string): Line =
  ## The permanent line for a failed file.
  @[span("failed", cRed, bold = true), span("    " & path & ": " & message)]

proc liveSink*(l: Live, stdoutWrite, stderrWrite: proc(s: string) {.closure, raises: [].}): Sink =
  ## Show the run on `l`.  The summary (and notes) are printed through
  ## `stdoutWrite` / `stderrWrite` when the run ends, after the display is gone.
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
      if ev.outcome == oFailed: l.print failureLine(ev.path, ev.message)
    of evFinish:
      l.finish()
      let lines = plainLines(ev, quiet = true)
      for line in lines.stdout: stdoutWrite line & "\n"
      for line in lines.stderr: stderrWrite line & "\n"
      return
    if l.due(): l.show(renderImport(sum, index, current))
