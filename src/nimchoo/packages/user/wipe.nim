## What goes when a user is removed (`nch users --delete`), and the words that say it.  The pause before any delete
## (the countdown) is in `confirm`; deleting the row is `users`.
##
## Everything belongs to a user through `on delete cascade`, so deleting the user row is enough to remove the
## user.  A later module that stores per-user data adds its table to `userTables`; a test checks that none is
## forgotten.

import std/[options, strformat]
import std/strutils
import ../db/statement
import ../db/store
import ../../core/errors

{.push raises: [].}

const userTables* = ["file", "seen_file", "selection"]
  ## the tables with a `user_id` that emptying a user clears (`user_profile` stays: it is the user's)

func counted*(n: int, one, many: string): string =
  ## "1 activity", "74 activities".
  fmt"{n} {(if n == 1: one else: many)}"

func describe*(parts: seq[string], user: string): string =
  ## What is to go when a user is removed: "74 activities and user bob", "3 activities, 2 notes and user bob" (the
  ## parts are what the packages say the user has: `user/has`), "user bob" if they say nothing.
  if parts.len == 0:
    fmt"user {user}"
  else:
    fmt"""{parts.join(", ")} and user {user}"""

proc findUser*(st: Store, name: string): UserId {.raises: [StoreError].} =
  ## The id of the user called `name`; an error if there is none.
  let id = st.db.queryOne(UserId, "select id from user where name = :name", name = name)
  if id.isNone:
    raiseStore("no such user: " & name)
  id.get
