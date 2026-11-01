## The live display of `nch import` (see ui/live.nim): two lines that follow the
## run and are left on screen, final numbers and all, when it ends.  Nothing is
## printed per file; failures are counted here and written in the log.
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
  ## at, `current`, if any) of `sum.total`.
  var first: Line = @[span("importing ", bold = true),
                      span(commas(index) & " / " & commas(sum.total))]
  if current.len > 0: first.add span("   " & current, dim = true)
  var second: Line
  second.add span("imported " & commas(sum.imported), cGreen)
  second.add span(dot, dim = true)
  second.add span("skipped " & commas(sum.skipped), dim = true)
  if sum.known > 0:
    second.add span(dot, dim = true)
    second.add span("known failures " & commas(sum.known), dim = true)
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

func doneLine*(sum: Summary, logPath: string): string =
  ## The line after the display: the summary, and where the details are if
  ## files failed.
  result = "done: " & summaryLine(sum)
  if sum.failed > 0 and logPath.len > 0:
    result.add "; details in " & logPath

proc liveSink*(l: Live, logPath: string,
               stdoutWrite, stderrWrite: proc(s: string) {.closure, raises: [].}): Sink =
  ## Show the run on `l`.  When it ends the last frame stays on screen, then
  ## `stdoutWrite` gets the done line and `stderrWrite` any notes.  `logPath`
  ## ("" if there is no log) is where failures are described.
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
      stdoutWrite doneLine(sum, logPath) & "\n"
      for note in ev.summary.notes: stderrWrite "warning: " & note & "\n"
      return
    if l.due(): l.show(renderImport(sum, index, current))
