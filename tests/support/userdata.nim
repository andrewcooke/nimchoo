## Helpers for tests that delete a user's data: fill a user with one of everything, count rows,
## make a second user.

import std/strutils
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/modules

proc count*(s: Store, table: string): int =
  parseInt(s.db.getValue(sql("select count(*) from " & table)))

proc fill*(s: Store, tag: string) =
  ## One of everything, for the user of `s`.
  let u = s.userId
  s.db.exec(sql"insert into file(user_id, name, sha256, imported_at) values (?, ?, ?, 0)",
            u, tag, tag)
  let f = s.db.getValue(sql"select id from file where user_id = ? and sha256 = ?", u, tag)
  s.db.exec(sql"""insert into activity(file_id, session, start_t, end_t)
                  values (?, 0, 0, 10)""", f)
  let a = s.db.getValue(sql"select max(id) from activity")
  s.db.exec(sql"insert into coords(activity_id, t, lon, lat) values (?, 5, 1.0, 2.0)", a)
  s.db.exec(sql"insert into segment(activity_id, n, start_t, end_t) values (?, 1, 0, 10)", a)
  s.db.exec(sql"insert into seen_file(user_id, path, size, mtime, file_id) values (?, ?, 1, 1, ?)",
            u, "/" & tag, f)
  s.db.exec(sql"insert into selection(user_id, activity_id) values (?, ?)", u, a)

func globals*(db: string, user = ""): Globals =
  Globals(dbPath: db, user: user, fragments: allFragments)

proc addUser*(path, name: string) =
  ## Make a user by hand (the command that does it is not what is being tested).
  let c = db_sqlite.open(path, "", "", "")
  c.exec(sql"insert or ignore into user(name) values (?)", name)
  c.close()

const tables* = ["file", "activity", "coords", "segment", "seen_file", "selection"]
