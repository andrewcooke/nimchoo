## What a module needs to add its own data to what `nch activities --import` reads from a FIT file,
## without the importer knowing about it: the importer is older than such modules, so
## they hand it an `ImportStep`.  A step names the `record` fields it wants (say
## `heart_rate`); the importer collects them in the one pass over the file and, for each
## activity, calls the step's `write` with the values in time order.

import std/tables
import ../../core/[errors, extension]
import ../../core/ids
import ../db/statement
import ../fit/time

{.push raises: [].}

type
  Sample* = object ## One reading of one field.
    t*: UnixTime
    v*: float

  Samples* = Table[string, seq[Sample]]
    ## The readings of an activity, by FIT field name: in time order, one per second at most.

  ImportStep* = object
    label*, labels*: string ## what it writes, one and many: "heart-rate reading(s)"
    channels*: seq[string] ## the `record` fields it wants
    write*: proc(db: DbConn, activityId: ActivityId, samples: Samples): int {.
      nimcall, raises: [StoreError]
    .}
      ## write the rows for an activity (inside the transaction that imports it);
      ## returns how many

  ExtraCount* = object ## How much of what a step wrote.
    n*: int
    one*, many*: string

const importStep* = ExtensionPoint[ImportStep](name: "importer/steps")
  ## What other packages add to an import: `heartrate` contributes its step to this (PACKAGES.md).
