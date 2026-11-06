## What happens during `nch activities --import`, as events.  The importer announces them
## and prints nothing; sinks (sinks.nim) decide what to do with them: print
## lines, draw a live display, write a log.  A sink gets every event of every
## file, so it must be cheap and must not raise.

import ../db/channel
import ../warnings
import ./failure

{.push raises: [].}

type
  Outcome* = enum
    oImported,          ## its activities are now in the database
    oDuplicate,         ## the same content was imported before (found by hash)
    oUnchanged,         ## the path, size and time are as last time: not read
    oKnownFailure,      ## failed last time and has not changed: not read
    oMonitor,        ## a monitor file (all-day wear data and the like: no activity expected): not a failure
    oFailed             ## failed now

  Counts* = object
    activities*, segments*, coords*: int
    extras*: seq[ExtraCount]    ## what modules' import steps wrote

  Summary* = object
    ## Totals so far, or at the end.
    total*: int                 ## files to look at
    done*: int                  ## files looked at
    imported*, duplicates*, unchanged*, failed*, known*, monitor*: int
    advisories*: int            ## things noticed in files (see warnings.nim), not files
    failures*: array[FailureKind, int]   ## `failed`, by kind
    notes*: seq[string]         ## things to say about the run itself

  EventKind* = enum evStart, evFileStart, evFileDone, evFinish

  ImportEvent* = object
    case kind*: EventKind
    of evStart:
      total*: int
    of evFileStart:
      startIndex*: int          ## 1-based
      startPath*: string
    of evFileDone:
      index*: int               ## 1-based
      path*: string
      outcome*: Outcome
      counts*: Counts           ## for oImported
      failure*: FailureKind     ## for oFailed and oKnownFailure
      message*: string          ## the reason, for those
      sameAs*: string           ## for oDuplicate: where that content was imported from
      advisories*: seq[Warning] ## oddities found in the file (not errors)
    of evFinish:
      summary*: Summary

  Sink* = proc(ev: ImportEvent) {.closure, raises: [].}

func fanOut*(sinks: seq[Sink]): Sink =
  ## One sink that passes each event to all of `sinks`, in order.
  result = proc(ev: ImportEvent) {.closure, raises: [].} =
    for s in sinks: s(ev)

func tally*(s: var Summary, ev: ImportEvent) =
  ## Count one finished file.
  if ev.kind != evFileDone: return
  inc s.done
  s.advisories += ev.advisories.len
  case ev.outcome
  of oImported: inc s.imported
  of oDuplicate: inc s.duplicates
  of oUnchanged: inc s.unchanged
  of oKnownFailure: inc s.known
  of oMonitor: inc s.monitor
  of oFailed:
    inc s.failed
    inc s.failures[ev.failure]
