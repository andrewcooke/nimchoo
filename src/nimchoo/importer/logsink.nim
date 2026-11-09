## The log of `nch activities --import`: what changed or went wrong, in full.  Each line is
## one of the shared events (ui/vocabulary.nim), so `nch log activities advisory` finds
## one kind: `start`, `imported`, `duplicate`, `failed`, `advisory` (something
## noticed in a file that was imported anyway), `note` (about the run), `done`.
## Files that were unchanged or known failures are not logged one by one (a
## re-import of thousands would fill the log); the `done` line counts them.  `-q`
## affects the screen only; the log is always complete.

import ../core/logfile
import ./events
import ./failure
import ./sinks

{.push raises: [].}

const command = "activities"

type Entry* = object
  level*: Level
  event*: LogEvent
  text*: string

func entry(level: Level, event: LogEvent, text: string): Entry =
  Entry(level: level, event: event, text: text)

func logEntries*(ev: ImportEvent): seq[Entry] =
  ## The log lines for an event.
  case ev.kind
  of evStart:
    result.add entry(lvInfo, leStart, plural(ev.total, "file", "files"))
  of evFileStart:
    discard
  of evFileDone:
    case ev.outcome
    of oImported:
      result.add entry(
        lvInfo,
        leImported,
        ev.path & "  " & plural(ev.counts.activities, "activity", "activities") & ", " &
          plural(ev.counts.segments, "segment", "segments") & ", " &
          plural(ev.counts.coords, "coordinate", "coordinates") & extrasText(ev.counts),
      )
    of oDuplicate:
      result.add entry(
        lvInfo,
        leDuplicate,
        ev.path & "  " & (
          if ev.sameAs.len > 0: "same content as " & ev.sameAs
          else: "already imported"
        ),
      )
    of oUnchanged, oKnownFailure, oMonitor:
      discard
    of oFailed:
      result.add entry(
        lvError, leFailed, ev.path & "  (" & ev.failure.label & ") " & ev.message
      )
    for w in ev.advisories:
      result.add entry(
        lvWarn, leAdvisory, ev.path & "  offset " & $w.offset & ": " & w.msg
      )
  of evFinish:
    for note in ev.summary.notes:
      result.add entry(lvWarn, leNote, note)
    result.add entry(lvInfo, leDone, summaryLine(ev.summary))

proc logSink*(l: Log): Sink =
  ## Write the entries of each event to `l`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for e in logEntries(ev):
      l.log(e.level, command, e.event, e.text)
