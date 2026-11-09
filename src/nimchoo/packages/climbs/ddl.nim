## The database tables of the climbs module (see core/fragment.nim).

import ../../core/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"), # sector (with retired), effort, climbs_done
  fragment("002-name-number.sql"), # sector.name_n
  fragment("003-effort-index.sql"), # effort(activity_id)
]
