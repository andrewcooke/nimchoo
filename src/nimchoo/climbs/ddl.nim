## The database tables of the climbs module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # sector (with retired), effort, climbs_done
  fragment("002-name-number.sql"),   # sector.name_n
]
