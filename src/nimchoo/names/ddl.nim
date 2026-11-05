## The database tables of the names module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # country, name_source, feature
  fragment("002-more-kinds.sql"),  # areas, water and more terrain are kept: the countries are read again
]
