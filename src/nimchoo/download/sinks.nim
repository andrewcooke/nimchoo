## Where download events go: into the log (every download, whichever command asked for it) and onto
## the screen (one line each, on stderr, so a pause for the network is explained).

import ../ui/[live, logfile, style]
import ./[fetch, spinner]

{.push raises: [].}

func fanOut*(sinks: seq[Sink]): Sink =
  ## One sink that passes each event to all of `sinks`.
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    for s in sinks:
      s(ev)

proc logSink*(l: Log, command: string): Sink =
  ## Write the events to the log as `command`: `downloaded` (info) and `failed` (error).
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    case ev.kind
    of deStarting:
      l.log(lvInfo, command, leNote, "need " & ev.message & "  " & ev.url)
    of deProgress, deReading, deFinished, deWorking, deWorkDone:
      discard # (the log has the start and the end)
    of deDownloaded:
      l.log(
        lvInfo,
        command,
        leDownloaded,
        ev.url & "  " & humanBytes(ev.bytes) & "  " & ev.path,
      )
    of deFailed:
      l.log(lvError, command, leFailed, ev.url & "  " & ev.message)

proc screenSink*(write: proc(line: string) {.closure, raises: [].}): Sink =
  ## Say each event, as a line (the progress is not: there is no animation without a terminal).
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    if ev.kind notin {deProgress, deReading, deFinished, deWorking, deWorkDone}:
      write describe(ev)

proc liveSink*(maker: proc(): Live {.nimcall, raises: [].} = newTerminalLive): Sink =
  ## Say a download on one line that turns a spinner (see spinner.nim) while the file comes and while it is read, and that
  ## stays on the screen at the end.  A file that is already in the cache and is only read gets the line and the spinner
  ## too, if the reading takes a moment, and the line goes at the end.
  var sp: Spinner
  var downloaded = false # this line is of a file that came now: it stays
  var label, url = ""
  var job = ""
    # the command's own job that is going on ("naming 1,112 activities"), if any
  proc endLine(ending: Ending, message = "") =
    if sp != nil:
      sp.stop(ending, message)
      sp = nil

  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    case ev.kind
    of deStarting:
      endLine(if downloaded: enKeep else: enClear)
        # (the last file's line, if it was not ended)
      downloaded = false
      label = ev.label
      url = ev.url
      sp = startSpinner(maker, label, url)
    of deProgress:
      discard # (the size is said when the line is done)
    of deDownloaded:
      downloaded = true
      if sp != nil:
        sp.setSize(ev.bytes)
    of deReading:
      if sp == nil:
        downloaded = false
        sp = startSpinner(maker, ev.label, ev.url)
    of deFinished:
      endLine(if downloaded: enKeep else: enClear)
      downloaded = false
      if job.len > 0:
        sp = startSpinner(maker, "", "", job) # (the job goes on)
    of deWorking:
      endLine(enClear)
      job = ev.label
      sp = startSpinner(maker, "", "", job)
    of deWorkDone:
      if sp == nil and ev.message.len > 0:
        sp = startSpinner(maker, "", "", job)
      endLine(if ev.message.len > 0: enKeep else: enClear, ev.message)
      job = ""
      downloaded = false
    of deFailed:
      if sp != nil:
        endLine(enFailed, ev.message)
      else:
        maker().keep(
          @[@[span("cannot download " & shortUrl(ev.url) & ": " & ev.message, red)]]
        )
      downloaded = false
