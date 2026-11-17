## The namers: what can propose a name for an activity (an extension point of this package, `namerPoint`).  Each namer is
## asked in order of its precedence, highest first, and the first that proposes a name wins (dev/NAMING.md): nothing is
## weighed.  A namer words the whole name itself (the shapes and their wording are in `rules.nim`, for those that want them)
## and may say nothing about an activity (none).  A namer may write its own package's tables while it proposes (naming is
## never run from a view).

import std/[algorithm, options]
import ../../core/[errors, extension]
import ../names/[countries, lookup]

{.push raises: [].}

type
  Ride* = object ## What a namer is told about an activity.
    id*: int64
    parts*: seq[Part] ## its stretches of riding, in order (none: it has no positions)
    start*: string ## where it started ("" if not known: see `rules.startText`)

  Propose* = proc(n: Names, ride: Ride, gpsErrors: var int): Option[string] {.
    nimcall, raises: [StoreError, DownloadError]
  .}
    ## A name for the ride, or none.  A search for a place not made because the positions were too far apart (bad GPS
    ## fixes) is counted in `gpsErrors`.

  Namer* = object
    name*: string ## "places"
    summary*: string ## one line
    precedence*: int ## asked before the namers with a lower one
    propose*: Propose

const namerPoint* = ExtensionPoint[Namer](name: "naming/namers")
  ## The namers: this package's (landmarks, places) and those of the packages above it (`climbs`: the big climb).

func inOrder*(all: seq[Namer]): seq[Namer] =
  ## The namers in the order they are asked: highest precedence first.
  result = all
  result.sort(
    proc(a, b: Namer): int =
      cmp(b.precedence, a.precedence)
  )
