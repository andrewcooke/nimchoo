## What goes when a user is removed (`nch users --delete`), and the words that say it.  The question before any delete
## is `core/ask`; deleting the row is `users`.
##
## Everything belongs to a user through `on delete cascade`, so deleting the user row is enough to remove the
## user.  A test checks that every table with a `user_id` column has it as a foreign key with `on delete cascade`, so that
## no table is forgotten.

import std/[options, strformat]
import std/strutils
import ../db/store
import ../../core/errors
import ./session

{.push raises: [].}

func describe*(parts: seq[string], user: string): string =
  ## What is to go when a user is removed: "74 activities and user bob", "3 activities, 2 notes and user bob" (the
  ## parts are what the packages say the user has: `user/has`), "user bob" if they say nothing.
  if parts.len == 0:
    fmt"user {user}"
  else:
    fmt"""{parts.join(", ")} and user {user}"""

proc findUser*(st: Store, name: string): UserId {.raises: [StoreError].} =
  ## The id of the user called `name`; an error if there is none.
  let id = st.db.lookupUser(name)
  if id.isNone:
    raiseStore("no such user: " & name)
  id.get
