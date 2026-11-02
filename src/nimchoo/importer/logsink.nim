## The log of `nch import`: what changed or went wrong, in full.  Every line's
## text starts with a word saying what it is, so one `grep -w` finds one kind:
## `start`, `imported`, `duplicate`, `failed`, `advisory` (something noticed in a
## file that was imported anyway), `note` (about the run), `done`.  Files that
## were unchanged or known failures are not logged one by one (a re-import of
## thousands would fill the log); the `done` line counts them.  `-q` affects the
## screen only; the log is always complete.

import std/strutils
import ../ui/logfile
import ./events
import ./failure
import ./sinks

{.push raises: [].}

const topic = "import"

type Entry* = object
  level*: Level
  text*: string

func entry(level: Level, word, text: string): Entry =
  Entry(level: level, text: word.alignLeft(9) & "  " & text)

func logEntries*(ev: ImportEvent): seq[Entry] =
  ## The log lines for an event.
  case ev.kind
  of evStart:
    result.add entry(lvInfo, "start", plural(ev.total, "file", "files"))
  of evFileStart: discard
  of evFileDone:
    case ev.outcome
    of oImported:
      result.add entry(lvInfo, "imported", ev.path & "  " &
        plural(ev.counts.activities, "activity", "activities") & ", " &
        plural(ev.counts.segments, "segment", "segments") & ", " &
        plural(ev.counts.coords, "coordinate", "coordinates"))
    of oDuplicate:
      result.add entry(lvInfo, "duplicate", ev.path & "  " &
        (if ev.sameAs.len > 0: "same content as " & ev.sameAs else: "already imported"))
    of oUnchanged, oKnownFailure: discard
    of oFailed:
      result.add entry(lvError, "failed", ev.path & "  (" & ev.failure.label & ") " &
        ev.message)
    for w in ev.advisories:
      result.add entry(lvWarn, "advisory", ev.path & "  offset " & $w.offset & ": " & w.msg)
  of evFinish:
    for note in ev.summary.notes:
      result.add entry(lvWarn, "note", note)
    result.add entry(lvInfo, "done", summaryLine(ev.summary))

proc logSink*(l: Log): Sink =
  ## Write the entries of each event to `l`.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for e in logEntries(ev): l.log(e.level, topic, e.text)
