## The database tables of the select module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"), # selection
  fragment("002-activity-index.sql")
]
