## Small helpers that only tests need (they used to be in src/): a sink that ignores download events, a run of the
## importer whose plain output is collected, and the import of one file with a profile already in hand.

import nimchoo/packages/download/fetch
import nimchoo/db/[channel, store]
import nimchoo/core/errors
import nimchoo/importer/[batch, events, importer, sinks]
import nimchoo/packages/fit/model
import nimchoo/packages/util/warnings/warnings

type Report* = ref object
  ## The plain output of a whole run, collected instead of printed.
  lines*, stderr*: seq[string]
  imported*, duplicates*, unchanged*, failed*, known*, advisories*: int

proc silent*(): fetch.Sink =
  ## A sink that ignores every event.
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    discard

proc reportSink(report: Report, quiet: bool): events.Sink =
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

proc importReport*(
    st: Store, targets: seq[string], opts: ImportOptions = ImportOptions()
): Report =
  ## `importPaths`, with the plain output collected in a Report.
  result = Report()
  discard importPaths(st, targets, opts, reportSink(result, opts.quiet))

proc importFile*(
    s: Store,
    p: Profile,
    name: string,
    data: seq[byte],
    ws: var seq[Warning],
    steps: seq[ImportStep] = @[],
): ImportResult {.raises: [FitError, ImportError, StoreError].} =
  ## `importFileWith` for a profile already in hand.
  importFileWith(
    s,
    proc(): Profile {.closure, raises: [].} =
      p,
    name,
    data,
    ws,
    steps,
  )
