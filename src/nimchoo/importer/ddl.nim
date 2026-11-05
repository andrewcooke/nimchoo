## The database tables of the importer module (see db/fragment.nim).

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # file, activity, coords, segment, seen_file
  fragment("002-names.sql"),    # activity.start_place and activity.name
]
