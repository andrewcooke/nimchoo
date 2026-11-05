## The database tables of the climbs module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # sector, effort, climbs_done
  fragment("002-retired.sql"),  # sector.retired
]
