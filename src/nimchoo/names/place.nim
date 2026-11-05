## Which place is this position near: the one question about places the rest of the program asks (the start of an
## activity, the country of a position that is inside no outline).  Callers do not know where the answer comes from.
## Today it is the list of towns and cities carried in the program (places/); the names of GeoNames, when a country's
## are loaded, are to come in front of it here, so that nothing else changes.

import std/options
import ../db/store
import ../errors
import ../places/seed

{.push raises: [].}

type Place* = object
  name*, country*: string       ## country: the two-letter ISO code
  distanceM*: float             ## from the position to the place
  id*: int64                    ## the row of the list carried in the program (`place`), what `activity.place_id` points to

proc placeAt*(st: Store, lon, lat: float): Option[Place] {.raises: [StoreError].} =
  ## The place nearest to the position, by distance on the ground; none only if there are no places at all.
  let found = nearestPlace(st.db, lon, lat)
  if found.isNone: return none(Place)
  some(Place(name: found.get.name, country: found.get.country, distanceM: found.get.distanceM, id: found.get.id))
