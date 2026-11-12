## Helpers for tests that delete a user's data: fill a user with one of everything, count rows,
## make a second user.

import nimchoo/packages/user/session
import nimchoo/packages/fit/time
import nimchoo/packages/importer/coord
import ./arrays
import nimchoo/packages/db/statement
import db_connector/db_sqlite
import nimchoo/core/globals
import nimchoo/packages/db/store
from nimchoo/registry import allFragments, allAccess, newAllAccess

proc count*(s: Store, table: string): int =
  s.db.scalar(int, "select count(*) from " & table)

proc fill*(s: Session, tag: string) =
  ## One of everything, for the user of `s`.
  let u = s.userId
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = u,
    name = tag,
    sha256 = tag,
  )
  let f = s.db.scalar(
    int64,
    "select id from file where user_id = :userId and sha256 = :sha256",
    userId = u,
    sha256 = tag,
  )
  s.db.execute(
    """insert into activity(file_id, session, start_t, end_t)
                  values (:fileId, 0, 0, 10)""",
    fileId = f,
  )
  let a = s.db.scalar(int64, "select max(id) from activity")
  s.db.putTrack(a, @[Coord(t: UnixTime(5), lon: 1.0, lat: 2.0)])
  s.db.execute(
    "insert into segment(activity_id, n, start_t, end_t) values (:activityId, 1, 0, 10)",
    activityId = a,
  )
  s.db.execute(
    "insert into seen_file(user_id, path, size, mtime, file_id) values (:userId, :path, 1, 1, :fileId)",
    userId = u,
    path = "/" & tag,
    fileId = f,
  )
  s.db.execute(
    "insert into selection(user_id, activity_id) values (:userId, :activityId)",
    userId = u,
    activityId = a,
  )

proc globals*(db: string, user = ""): Globals =
  Globals(
    dbPath: db, user: user, fragments: allFragments, access: allAccess, offline: true
  ) # (no test uses the network)

proc addUser*(path, name: string) =
  ## Make a user by hand (the command that does it is not what is being tested).
  let c = db_sqlite.open(path, "", "", "")
  c.execute("insert or ignore into user(name) values (:name)", name = name)
  c.close()

const tables* = ["file", "activity", "track", "segment", "seen_file", "selection"]
