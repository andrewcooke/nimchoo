## The database tables of the importer module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"), # file, activity, coords, segment, route, seen_file
  fragment("002-seen-file-index.sql")
]
