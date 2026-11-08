## The database tables of the names module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"), # country, coverage, feature
  fragment("002-country-cells.sql"), # country_cell, country_cell_done
  fragment("003-country-cell-index.sql")
]
