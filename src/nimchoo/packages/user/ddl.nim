## The database tables of the user module (see core/fragment.nim).

import ../../core/fragment

{.push raises: [].}

const fragments* = @[
  fragment("001-schema.sql") # user_profile
]
