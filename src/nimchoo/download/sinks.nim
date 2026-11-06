## Where download events go: into the log (every download, whichever command asked for it) and onto
## the screen (one line each, on stderr, so a pause for the network is explained).

import ../ui/[live, logfile, style]
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
    of deStarting:
      l.log(lvInfo, command, leNote, "need " & ev.message & "  " & ev.url)
    of deProgress:
      discard                    # (the log has the start and the end)
    of deDownloaded:
      l.log(lvInfo, command, leDownloaded, ev.url & "  " & humanBytes(ev.bytes) & "  " & ev.path)
    of deFailed:
      l.log(lvError, command, leFailed, ev.url & "  " & ev.message)

proc screenSink*(write: proc(line: string) {.closure, raises: [].}): Sink =
  ## Say each event, as a line (the progress is not: there is no animation without a terminal).
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    if ev.kind != deProgress: write describe(ev)

const spinnerFrames* = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

func progressLine*(label, url: string, bytes: int64, frame: int, finished: bool): Line =
  ## The line while a file comes, and after:
  ##
  ##     need locations in CL: download.geonames.org/export/dump/CL.zip (71.3MB) ⠹
  ##
  ## The address is grey; `bytes` is the size (0: not known yet, and nothing is said); the spinner turns with `frame` and
  ## goes when the file is `finished`.
  result = @[span("need " & label & ": "), span(shortUrl(url), grey)]
  if bytes > 0: result.add span(" (" & humanBytes(bytes) & ")")
  if not finished: result.add span(" " & spinnerFrames[frame mod spinnerFrames.len])

proc liveSink*(live: Live): Sink =
  ## Say a download on one line that turns a spinner while the file comes, and stays on the screen at the end.  A file
  ## that comes in a moment is only the finished line.
  var label, url = ""
  var total = 0'i64
  var frame = 0
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    case ev.kind
    of deStarting:
      label = ev.label
      url = ev.url
      total = 0
      frame = 0
    of deProgress:
      if ev.total > 0: total = ev.total
      inc frame
      if live.due(): live.show(@[progressLine(label, url, total, frame, false)])
    of deDownloaded:
      live.keep(@[progressLine(label, url, ev.bytes, frame, true)])
    of deFailed:
      live.keep(@[@[span("cannot download " & shortUrl(ev.url) & ": " & ev.message, red)]])
