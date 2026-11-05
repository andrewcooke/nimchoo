## The database tables of the places module (see db/fragment.nim).  Nothing uses them any more: see 002-empty.sql.

import ../db/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql"),   # place (no longer filled)
  fragment("002-empty.sql"),    # the list the program carried is gone: the table is emptied
]
