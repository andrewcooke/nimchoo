## The live display of `nch import` (see packages/ui/live.nim): two lines that follow the
## run and are left on screen, final numbers and all, when it ends.  Nothing is
## printed per file; failures are counted here and written in the log.
##
##     importing 1,204 / 3,000   2018-08-27-rec.fit
##     imported 3 · unchanged 1,196 · failed 5 (no activity 4, bad format 1) · advisories 17
##
## `renderImport` is a pure function of the counts, so it is tested without a
## terminal; the sink only keeps the counts and asks the Live when to draw.

import std/os
import ../ui/[live, markup]
import ../ui/style
import ../ui/vocabulary
import ../../core/globals
import ./sinks
import ./events
import ../ui/units

{.push raises: [].}

func renderImport*(sum: Summary, index: int, current: string): seq[Line] =
  ## The lines for the run so far: file number `index` (the one being looked
  ## at, `current`, if any) of `sum.total`.  What is zero is left out, except
  ## imported and failed.
  var first = ~"<em importing >{count(index)} / {count(sum.total)}"
  if current.len > 0:
    first.add ~"<hide    {current}>"
  var second: Line
  template part(l: Line) =
    if second.len > 0:
      second.add ~"<hide  · >"
    second.add l

  # the styles are those of the events of the same name (packages/ui/vocabulary.nim)
  part ~"<{leImported} imported {count(sum.imported)}>"
  if sum.duplicates > 0:
    part ~"<{leDuplicate} duplicates {count(sum.duplicates)}>"
  if sum.unchanged > 0:
    part ~"<{leUnchanged} unchanged {count(sum.unchanged)}>"
  if sum.monitor > 0:
    part ~"<{leUnchanged} monitor {count(sum.monitor)}>"
  if sum.known > 0:
    part ~"<{leUnchanged} known failures {count(sum.known)}>"
  if sum.failed > 0:
    part ~"<{leFailed} failed {count(sum.failed)} ({failureBreakdown(sum)})>"
  else:
    part ~"<{leUnchanged} failed 0>" # (nothing to see: dim)
  if sum.advisories > 0:
    part ~"<{leAdvisory} advisories {count(sum.advisories)}>"
  @[first, second]

func readLine*(sum: Summary): Line =
  ## The line after the display: the summary of the files read.  It does not say "done:", because what follows (the
  ## names, the selection) is not over yet.
  ~"read: " & summaryLine(sum)

proc liveSink*(
    l: Live,
    logged: bool,
    stdoutWrite, stderrWrite: proc(l: Line) {.closure, raises: [].},
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
      stdoutWrite readLine(sum)
      for note in ev.summary.warnings:
        stderrWrite warnLine(note)
      let hint = moreHint(sum, logged)
      if hint.len > 0:
        stderrWrite hint
      return
    if l.due():
      l.show(renderImport(sum, index, current))
