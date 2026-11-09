## Removing a user and what belongs to them (`nch users --delete`), and the words that say what goes.  The pause
## before any delete (the countdown) is in `confirm`.
##
## Everything belongs to a user through `on delete cascade`, so deleting the user row is enough to remove the
## user.  A later module that stores per-user data adds its table to `userTables`; a test checks that none is
## forgotten.

import std/options
import ../db/statement
import ../db/store
import ../../core/errors

{.push raises: [].}

const userTables* = ["file", "seen_file", "selection"]
  ## the tables with a `user_id` that emptying a user clears (`user_profile` stays: it is the user's)

func activities(n: int): string =
  $n & (if n == 1: " activity" else: " activities")

func describe*(count: Option[int], user: string): string =
  ## What is to go when a user, or everything, is removed: "74 activities for all users",
  ## "74 activities and user bob"; "all data" if the count is not known.
  let items =
    if count.isSome:
      activities(count.get)
    else:
      "all data"
  if user.len == 0:
    items & " for all users"
  else:
    items & " and user " & user

proc findUser*(st: Store, name: string): UserId {.raises: [StoreError].} =
  ## The id of the user called `name`; an error if there is none.
  let id = st.db.queryOne(UserId, "select id from user where name = :name", name = name)
  if id.isNone:
    raiseStore("no such user: " & name)
  id.get

proc removeUser*(st: Store, id: UserId) {.raises: [StoreError].} =
  ## Delete the user and everything they have.  (If it was the default user another
  ## becomes the default, or if there is none a new empty one is made, the next time the
  ## database is opened.)
  st.db.execute("delete from user where id = :id", id = id)
  st.reclaim()
