## Choosing the name of a climb from the features near it.  Pure: the rules, and nothing else.
##
## There are three tiers, tried in turn, and the first that gives a name wins:
##   1. a feature within 1 km of the end of the climb (its top): the name itself;
##   2. else a feature within 1.5 km of the middle: the name, with "near" in front if it is 1 km or more away;
##   3. else a populated place within 5 km of the middle: "near <place>".
## Inside a tier the kinds are tried in a fixed order, and the first kind that has anything in range wins, however
## much further than a later kind it is: a pass or saddle, a peak or mountain, a hill / ridge / spur / valley /
## canyon, a village or town, a neighbourhood.  Within a kind the closest wins.  Abandoned, destroyed and historical
## places are never used.  They are labels, not facts: the nearest named hill is often not what the climb is called.

import std/options

{.push raises: [].}

const
  endRadiusM* = 1000.0         ## tier 1: from the end of the climb
  middleRadiusM* = 1500.0      ## tier 2: from the middle
  townRadiusM* = 5000.0        ## tier 3: from the middle
  nearFromM* = 1000.0          ## in tier 2, a feature this far or further is only "near" the climb

type
  Candidate* = object
    ## A feature near the route.
    name*, code*: string       ## GeoNames feature code (PASS, PK, HLL, PPL, PPLX...)
    isPlace*: bool             ## a populated place (class P), not terrain
    fromTopM*: float           ## distance from the end of the climb (its last point)
    fromMiddleM*: float        ## distance from the middle of the climb (half way along it)

  PickKind* = enum
    pkLandmark = "landmark", pkPass = "pass", pkPeak = "peak", pkHill = "hill", pkTown = "town", pkNeighbourhood = "neighbourhood"

  Pick* = object
    name*: string              ## what to show: the feature's name, or "near <name>"
    kind*: PickKind
    tier*: int                 ## 1, 2 or 3
    distanceM*: float          ## the distance that decided (from the end in tier 1, from the middle otherwise)

func kindOf(c: Candidate): Option[PickKind] =
  case c.code
  of "PASS", "SDL": some(pkPass)
  of "PK", "PKS", "MT", "MTS": some(pkPeak)
  of "HLL", "HLLS", "RDGE", "SPUR", "VAL", "CNYN": some(pkHill)
  of "PPLQ", "PPLW", "PPLH": none(PickKind)                 # abandoned, destroyed, historical
  of "PPLX": some(pkNeighbourhood)
  else: (if c.isPlace: some(pkTown) else: none(PickKind))

func pickClimbName*(candidates: openArray[Candidate]): Option[Pick] =
  ## The name for a climb among the features near it, if there is one.
  for tier in 1 .. 3:
    let limit = [endRadiusM, middleRadiusM, townRadiusM][tier - 1]
    var best: array[PickKind, Option[Pick]]
    for c in candidates:
      let kind = kindOf(c)
      if kind.isNone: continue
      if tier == 3 and not c.isPlace: continue                 # (the last chance is a place)
      let distance = if tier == 1: c.fromTopM else: c.fromMiddleM
      if distance > limit: continue
      if best[kind.get].isNone or distance < best[kind.get].get.distanceM:
        let near = tier == 3 or (tier == 2 and distance >= nearFromM)
        best[kind.get] = some(Pick(name: (if near: "near " & c.name else: c.name), kind: kind.get,
                                   tier: tier, distanceM: distance))
    for kind in PickKind:                                       # (the order of the enum is the order of preference)
      if best[kind].isSome: return best[kind]
