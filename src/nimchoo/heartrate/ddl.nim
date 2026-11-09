## The database tables of the heartrate module (see db/fragment.nim).

import ../core/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql") # heartrate
]
