## The database tables of the model module (see core/fragment.nim).

import ../core/fragment
import ./models

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion),
  fragment("002-impulse-index.sql"), # ff_model (with `default`), impulse
]
