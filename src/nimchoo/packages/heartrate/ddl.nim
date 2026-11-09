## The database tables of the heartrate module (see core/fragment.nim).

import ../../core/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql") # heartrate
]
