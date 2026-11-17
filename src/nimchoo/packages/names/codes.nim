## The GeoNames feature codes that the naming rules treat specially, in one place so that the rules for activities
## (`activity.nim`) and for climbs (`climbpick.nim`) cannot drift apart.  Pure.

{.push raises: [].}

const
  inactivePlaceCodes* = ["PPLQ", "PPLW", "PPLH"]
    ## populated places that are abandoned, destroyed or historical: labels, not places, so never used
  neighbourhoodCode* = "PPLX" ## a section of a populated place
  passCodes* = ["PASS", "SDL"] ## a pass or saddle
  peakCodes* = ["PK", "PKS", "MT", "MTS"] ## a peak or mountain (one or several)
  hillCodes* = ["HLL", "HLLS"] ## a hill (one or several)

func isInactivePlace*(code: string): bool =
  ## An abandoned, destroyed or historical populated place.
  code in inactivePlaceCodes
