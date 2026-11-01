## The log of `nch import`: what changed or went wrong, in full.  Files that
## were skipped as unchanged or as known failures are not logged one by one
## (a re-import of thousands would fill the log); the final line counts them.
## `-q` affects the screen only; the log is always complete.

import ../ui/logfile
import ./events
import ./failure
import ./sinks

{.push raises: [].}

const topic = "import"

type Entry* = object
  level*: Level
  text*: string

func logEntries*(ev: ImportEvent): seq[Entry] =
  ## The log lines for an event.
  case ev.kind
  of evStart:
    result.add Entry(level: lvInfo, text: "start: " & plural(ev.total, "file", "files"))
  of evFileStart: discard
  of evFileDone:
    case ev.outcome
    of oImported:
      result.add Entry(level: lvInfo, text: ev.path & "  imported " &
        plural(ev.counts.activities, "activity", "activities") & ", " &
        plural(ev.counts.segments, "segment", "segments") & ", " &
        plural(ev.counts.coords, "coordinate", "coordinates"))
    of oAlreadyImported:
      result.add Entry(level: lvInfo, text: ev.path & "  already imported")
    of oUnchanged, oKnownFailure: discard
    of oFailed:
      result.add Entry(level: lvError, text: ev.path & "  failed (" &
        ev.failure.label & "): " & ev.message)
    for w in ev.warnings:
      result.add Entry(level: lvWarn, text: ev.path & "  offset " & $w.offset &
        ": " & w.msg)
  of evFinish:
    for note in ev.summary.notes:
      result.add Entry(level: lvWarn, text: note)
    result.add Entry(level: lvInfo, text: "done: " & summaryLine(ev.summary))

proc logSink*(l: Log): Sink =
  ## Write the entries of each event to `l`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for e in logEntries(ev): l.log(e.level, topic, e.text)
