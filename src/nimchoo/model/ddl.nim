## The database tables of the model module (see db/fragment.nim).

import ../db/fragment
import ./models

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion),   # ff_model (with `default`), impulse
]
