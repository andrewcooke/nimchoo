## What happens during `nch import`, as events.  The importer announces them
## and prints nothing; sinks (sinks.nim) decide what to do with them: print
## lines, draw a live display, write a log.  A sink gets every event of every
## file, so it must be cheap and must not raise.

import ./channel
import ../util/warnings/warnings
import ./failure

{.push raises: [].}

type
  Outcome* = enum
    oImported ## its activities are now in the database
    oDuplicate ## the same content was imported before (found by hash)
    oUnchanged ## the path, size and time are as last time: not read
    oKnownFailure ## failed last time and has not changed: not read
    oMonitor
      ## a monitor file (all-day wear data and the like: no activity expected): not a failure
    oFailed ## failed now

  Counts* = object
    activities*, stretches*, coords*: int
    extras*: seq[ExtraCount] ## what modules' import steps wrote

  Summary* = object ## Totals so far, or at the end.
    total*: int ## files to look at
    done*: int ## files looked at
    imported*, duplicates*, unchanged*, failed*, known*, monitor*: int
    advisories*: int ## things noticed in files (see packages/util/warnings), not files
    failures*: array[FailureKind, int] ## `failed`, by kind
    warnings*: seq[string]
      ## what went wrong with the run itself, the work done all the same

  EventKind* = enum
    evStart
    evFileStart
    evFileDone
    evFinish

  ImportEvent* = object
    case kind*: EventKind
    of evStart:
      total*: int
    of evFileStart:
      startIndex*: int ## 1-based
      startPath*: string
    of evFileDone:
      index*: int ## 1-based
      path*: string
      advisories*: seq[Warning] ## oddities found in the file (not errors)
      case outcome*: Outcome
      of oImported:
        counts*: Counts
      of oDuplicate:
        sameAs*: string ## where that content was imported from ("" if not known)
      of oUnchanged:
        discard
      of oKnownFailure, oMonitor, oFailed:
        failure*: FailureKind
        message*: string ## the reason
    of evFinish:
      summary*: Summary

func fileDoneEvent*(
    index: int,
    path: string,
    outcome: Outcome,
    advisories: seq[Warning] = @[],
    counts = Counts(),
    failure = fkBadFormat,
    message = "",
    sameAs = "",
): ImportEvent =
  ## The event of a file that is done: only what belongs to its outcome is kept (`counts` of an imported file, `sameAs` of a
  ## duplicate, `failure` and `message` of those that failed or are known to), so that none is made that says more.
  case outcome
  of oImported:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oImported,
      counts: counts,
    )
  of oDuplicate:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oDuplicate,
      sameAs: sameAs,
    )
  of oUnchanged:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oUnchanged,
    )
  of oKnownFailure:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oKnownFailure,
      failure: failure,
      message: message,
    )
  of oMonitor:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oMonitor,
      failure: failure,
      message: message,
    )
  of oFailed:
    ImportEvent(
      kind: evFileDone,
      index: index,
      path: path,
      advisories: advisories,
      outcome: oFailed,
      failure: failure,
      message: message,
    )

type Sink* = proc(ev: ImportEvent) {.closure, raises: [].}

func fanOut*(sinks: seq[Sink]): Sink =
  ## One sink that passes each event to all of `sinks`, in order.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for s in sinks:
      s(ev)

func tally*(s: var Summary, ev: ImportEvent) =
  ## Count one finished file.
  if ev.kind != evFileDone:
    return
  inc s.done
  s.advisories += ev.advisories.len
  case ev.outcome
  of oImported:
    inc s.imported
  of oDuplicate:
    inc s.duplicates
  of oUnchanged:
    inc s.unchanged
  of oKnownFailure:
    inc s.known
  of oMonitor:
    inc s.monitor
  of oFailed:
    inc s.failed
    inc s.failures[ev.failure]
