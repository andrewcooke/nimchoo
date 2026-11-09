## Deleting what belongs to a user: all of it but the user, or the user too
## (`nch users --delete`), with the words and the countdown both use.  Nothing is deleted without
## `--force`, and on a terminal there are then a few seconds in which to press Ctrl-C.
##
## Everything belongs to a user through `on delete cascade`, so deleting the user row is enough
## to remove the user.  A
## later module that stores per-user data adds its table to `userTables`; a test checks that
## none is forgotten.  This module counts activities, and `describe` says so; a later module
## that stores data it wants mentioned adds a line there (it is deleted either way).

import std/[options, os]
import db_connector/db_sqlite
import ../core/globals
import ../db/[statement, store]
import ../core/errors
import ../packages/ui/live
import ../packages/ui/style

{.push raises: [].}

const
  userTables* = ["file", "seen_file", "selection"]
    ## the tables with a `user_id` that emptying a user clears (`user_profile` stays: it is the user's)
  waitSeconds* = 5

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

func countdownLine*(what: string, seconds: int): Line =
  ## "deleting WHAT in 5 s ... (Ctrl-C to cancel)", in red.
  @[
    span("deleting " & what & " in ", red),
    span($seconds, red, bold = true),
    span(" s ... (Ctrl-C to cancel)", red),
  ]

proc countdown*(
    l: Live, what: string, seconds: int, wait: proc(ms: int) {.closure, raises: [].}
) =
  ## Show the line once a second, from `seconds` down to 1, then take it away.
  for s in countdown(seconds, 1):
    l.show @[countdownLine(what, s)]
    wait 1000
  l.finish()

proc sayDeleted*(text: string) =
  ## The line that says what was deleted ("done: deleted ..."), in red on a terminal, so that it stands out.
  stdout.say render(@[span("done: " & text, red)], canColourStdout()) & "\n"

proc sleepMs*(ms: int) {.raises: [].} =
  ## Wait for `ms` milliseconds.
  try:
    sleep(ms)
  except OSError:
    discard

proc countActivities*(path, user: string): Option[int] =
  ## How many activities there are (of `user`, if given), counted straight from
  ## the file, so that it works whatever layout the database has (the one
  ## thing it needs is a table called `activity`).  None if that fails.
  var db: DbConn
  try:
    db = open(path, "", "", "")
  except DbError:
    return none(int)
  defer:
    try:
      db.close()
    except DbError:
      discard
  try:
    result =
      if user.len == 0:
        some(db.scalar(int, "select count(*) from activity"))
      else:
        some(
          db.scalar(
            int,
            """select count(*) from activity a
                                join file f on f.id = a.file_id
                                where f.user_id = (select id from user where name = :name)""",
            name = user,
          )
        )
  except StoreError:
    result = none(int)

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
