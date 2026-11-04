## The database tables of the places module (see db/fragment.nim).

import ../db/fragment
import ./[data, seed]

{.push raises: [].}

const
  schema = fragment("001-schema.sql")
  fragments* = @[
    # `place`, filled with the list in use (see data.nim).  The list is not part of the checksum:
    # when it changes (the author's own list, or a newer one in the program) the places are replaced
    # (`reloadPlaces`).  Databases made when it was part of the checksum are still accepted.
    schema.withSeed(seedPlaces)
          .withReseed(placesVersion, reloadPlaces)
          .withLegacy(@[checksum(schema.withSeed(seedPlaces, dataVersion))], dataVersion),
  ]
