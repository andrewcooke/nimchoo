## The database tables of the climbs module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # sector, effort, climbs_done
  fragment("002-name.sql"),     # sector.name
  fragment("003-names.sql"),    # sector.manual; the automatic names are made again
  fragment("004-no-kind.sql"),  # sector.kind is dropped (never used)
]
