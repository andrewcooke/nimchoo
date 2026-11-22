## Why a file could not be imported, in a few kinds, counted on screen.  Those the file's content decides are
## remembered in the database (so a known failure is not tried again: `remembered`); the others are tried again.

import std/options
import ../../core/errors

{.push raises: [].}

type FailureKind* = enum
  fkNoActivity = "no_activity" ## no activity in the file (not a ride)
  fkMonitor = "monitor"
    ## a file of another type than activity (monitoring...): no activity expected
  fkBadTime = "bad_time" ## times that are not calendar times
  fkBadFormat = "bad_format" ## not a readable FIT file
  fkUnreadable = "unreadable" ## the file could not be read
  fkNotFound = "not_found" ## no such path, or nothing to import in it
  fkStore = "database" ## the database refused

func remembered*(k: FailureKind): bool =
  ## Whether the failure is the file's own (its content decides it), and so is kept with the file's size and time and
  ## not tried again; a failure of the moment (the database busy, a file that could not be read) is tried again.
  case k
  of fkNoActivity, fkMonitor, fkBadTime, fkBadFormat: true
  of fkUnreadable, fkNotFound, fkStore: false

func failureOf*(e: ref NchError): FailureKind =
  ## The kind of failure an error stands for.
  if e of ImportError:
    case ((ref ImportError)(e)).kind
    of ifNoActivity: fkNoActivity
    of ifBadTime: fkBadTime
    of ifMonitor: fkMonitor
  elif e of FitError:
    fkBadFormat
  elif e of StoreError:
    fkStore
  else:
    fkBadFormat

func label*(k: FailureKind): string =
  ## The kind in words, for people.
  case k
  of fkNoActivity: "no activity"
  of fkMonitor: "monitor"
  of fkBadTime: "bad time"
  of fkBadFormat: "bad format"
  of fkUnreadable: "unreadable"
  of fkNotFound: "not found"
  of fkStore: "database"

func kindOf*(label: string): Option[FailureKind] =
  ## The kind with this stored label (`$kind`); none for a label that is not one.
  for k in FailureKind:
    if $k == label:
      return some(k)
  none(FailureKind)
