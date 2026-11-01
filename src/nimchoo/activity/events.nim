## What happens during `nch import`, as events.  The importer announces them
## and prints nothing; sinks (sinks.nim) decide what to do with them: print
## lines, draw a live display, write a log.  A sink gets every event of every
## file, so it must be cheap and must not raise.

import ../warnings
import ./failure

{.push raises: [].}

type
  Outcome* = enum
    oImported,          ## its activities are now in the database
    oAlreadyImported,   ## the same content was imported before (found by hash)
    oUnchanged,         ## the path, size and time are as last time: not read
    oKnownFailure,      ## failed last time and has not changed: not read
    oFailed             ## failed now

  Counts* = object
    activities*, segments*, coords*: int

  Summary* = object
    ## Totals so far, or at the end.
    total*: int                 ## files to look at
    done*: int                  ## files looked at
    imported*, skipped*, failed*, known*: int
    warnings*: int
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
      warnings*: seq[Warning]
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
  s.warnings += ev.warnings.len
  case ev.outcome
  of oImported: inc s.imported
  of oAlreadyImported, oUnchanged: inc s.skipped
  of oKnownFailure: inc s.known
  of oFailed:
    inc s.failed
    inc s.failures[ev.failure]
