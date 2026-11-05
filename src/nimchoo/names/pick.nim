## Choosing the name of a climb from the features near it.  Pure: the rules, and nothing else.
##
## In order of preference:
##   1. a pass or saddle (PASS, SDL) within 400 m of the top of the climb: "Paso Los Libertadores";
##   2. a peak or mountain (PK, PKS, MT, MTS) within 1 km of the top;
##   3. a hill, ridge or spur (HLL, HLLS, RDGE, SPUR) within 1.5 km of the top;
##   4. the nearest populated place within 5 km of the middle of the climb: "near Lo Barnechea".
## Terrain is measured from the top only: a climb ends at its mountain, it does not start there.  A place says
## where the climb is as a whole, so it is measured from the middle.  The nearest wins within a kind.  A feature
## more than 1 km away gives "near <name>" and not the name itself.  They are labels, not facts: the nearest named hill
## is often not what the climb is called.

import std/options

{.push raises: [].}

const
  passRadiusM* = 400.0         ## from the top
  peakRadiusM* = 1000.0        ## from the top
  hillRadiusM* = 1500.0        ## from the top
  townRadiusM* = 5000.0        ## from the middle
  nearAboveM* = 1000.0         ## further than this a feature is only "near" the climb

type
  Candidate* = object
    ## A feature near the route.
    name*, code*: string       ## GeoNames feature code (PASS, PK, HLL, PPL...)
    isPlace*: bool             ## a populated place (class P), not terrain
    fromTopM*: float           ## distance from the top of the climb (its last point)
    fromMiddleM*: float        ## distance from the middle of the climb (half way along it)

  PickKind* = enum pkPass = "pass", pkPeak = "peak", pkHill = "hill", pkNear = "near"

  Pick* = object
    name*: string              ## what to show: the feature's name, or "near <place>"
    kind*: PickKind
    distanceM*: float          ## the distance that decided (from the top, or from the route)

func kindOf(code: string): Option[PickKind] =
  case code
  of "PASS", "SDL": some(pkPass)
  of "PK", "PKS", "MT", "MTS": some(pkPeak)
  of "HLL", "HLLS", "RDGE", "SPUR": some(pkHill)
  else: none(PickKind)

func pickName*(candidates: openArray[Candidate]): Option[Pick] =
  ## The name for a climb among the features near it, if there is one.
  var best: array[PickKind, Option[Pick]]
  for c in candidates:
    var kind: PickKind
    var distance: float
    if c.isPlace:
      distance = c.fromMiddleM
      if distance > townRadiusM: continue
      kind = pkNear
    else:
      let k = kindOf(c.code)
      if k.isNone: continue
      kind = k.get
      case kind
      of pkPass:
        if c.fromTopM > passRadiusM: continue
        distance = c.fromTopM
      of pkPeak:
        if c.fromTopM > peakRadiusM: continue
        distance = c.fromTopM
      of pkHill:
        if c.fromTopM > hillRadiusM: continue
        distance = c.fromTopM
      of pkNear: continue
    if best[kind].isNone or distance < best[kind].get.distanceM:
      best[kind] = some(Pick(name: (if kind == pkNear or distance > nearAboveM: "near " & c.name else: c.name),
                             kind: kind, distanceM: distance))
  for kind in [pkPass, pkPeak, pkHill, pkNear]:
    if best[kind].isSome: return best[kind]
