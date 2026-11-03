## The database tables of the places module (see db/fragment.nim).

import ../db/fragment
import ./seed

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql").withSeed(seedPlaces),   # place, filled with the list the program carries
]
