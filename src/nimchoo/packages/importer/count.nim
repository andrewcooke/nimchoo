## Counting the activities in a database file, for the words that say what a delete would remove.

import std/options
import db_connector/db_sqlite
import ../db/statement
import ../../core/errors

{.push raises: [].}

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
