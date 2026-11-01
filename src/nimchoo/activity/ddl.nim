## The database tables of the activity module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-tables.sql", 1),   # file, activity, coords
  fragment("002-segment.sql"),              # segment
]
