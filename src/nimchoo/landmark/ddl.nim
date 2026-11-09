## The database tables of the landmark module (see db/fragment.nim).

import ../core/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql") # landmark
]
