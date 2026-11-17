## A place by its name, for a command that takes one where a position is wanted (`nch activities --near Providencia`): the
## author's landmarks first, then the GeoNames features already loaded (`feature`: the countries where the rides are; nothing is
## downloaded), compared without regard to case or accents.  Among the features, populated places come first, the biggest
## first; then the rest, the biggest first.  Pure database code.

import std/options
import ../db/statement
import ../db/store
import ../../core/errors
import ./codes

{.push raises: [].}

type NamedPlace* = object
  name*: string ## as it is spelt there
  lon*, lat*: float
  what*: string ## "your landmark", "a populated place (PPLA3)", "a feature (HLL)"

proc placesNamed*(st: Store, text: string): seq[NamedPlace] {.raises: [StoreError].} =
  ## The places called `text`, the likeliest first (see above); none if there is none.
  for r in st.db.query(
    tuple[name: string, lon, lat: float],
    "select name, lon, lat from landmark where fold(name) = fold(:text) order by name",
    text = text,
  ):
    result.add NamedPlace(name: r.name, lon: r.lon, lat: r.lat, what: "your landmark")
  for r in st.db.query(
    tuple[name, class, code: string, population: Option[int64], lon, lat: float],
    """select name, class, code, population, X(geom), Y(geom) from feature
        where fold(name) = fold(:text) and geom is not null
        order by class = 'P' desc, coalesce(population, 0) desc, id""",
    text = text,
  ):
    if r.class == "P" and r.code.isInactivePlace:
      continue
    let what =
      if r.class == "P":
        "a populated place (" & r.code & ")"
      else:
        "a feature (" & r.code & ")"
    result.add NamedPlace(name: r.name, lon: r.lon, lat: r.lat, what: what)
