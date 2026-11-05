## Where download events go: into the log (every download, whichever command asked for it) and onto
## the screen (one line each, on stderr, so a pause for the network is explained).

import ../ui/logfile
import ./fetch

{.push raises: [].}

func fanOut*(sinks: seq[Sink]): Sink =
  ## One sink that passes each event to all of `sinks`.
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    for s in sinks: s(ev)

proc logSink*(l: Log, command: string): Sink =
  ## Write the events to the log as `command`: `downloaded` (info) and `failed` (error).
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    case ev.kind
    of deDownloaded:
      l.log(lvInfo, command, leDownloaded, ev.url & "  " & humanBytes(ev.bytes) & "  " & ev.path)
    of deFailed:
      l.log(lvError, command, leFailed, ev.url & "  " & ev.message)

proc screenSink*(write: proc(line: string) {.closure, raises: [].}): Sink =
  ## Say each event, as a line.
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    write describe(ev)
