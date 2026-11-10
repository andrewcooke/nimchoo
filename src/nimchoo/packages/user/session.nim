## The user whose data a command works on, and the database it works in: a `Session`.  `openSession` opens the
## database (`openStore`) and finds the user: the one asked for (`--user`), else the default.  A command that has a
## user starts with it; one that has none (the landmarks, which are everybody's) opens the `Store` alone.
##
## One user is the default (`user.is_default`): the one used when none is asked for.  A database with no users
## gets one, called `default`; if the default user has gone but others remain, the oldest of them becomes the
## default.
##
## A `Session` is used where a `Store` is (it converts), so only what needs the user says `Session`.

import std/options
import ../../core/[errors, globals, ids]
import ../../core/access
import ../db/[statement, store]
export ids

{.push raises: [].}

const defaultUser* = "default" ## the name of the user made in an empty database

type Session* = object
  store*: Store
  db*: DbConn ## the connection, as `store.db` (so that a session is used as a store is)
  path*: string ## the database file, as `store.path`
  userId*: UserId
  userName*: string

converter toStore*(s: Session): Store =
  s.store

proc close*(s: Session) {.raises: [].} =
  close(s.store)

proc openSession*(
    path: string, fragments: seq[Fragment], user = "", access: Access = nil
): Session {.raises: [StoreError].} =
  ## Open the database at `path` (as `openStore`) and find `user` ("": the default user, made if there are no
  ## users).  Raises StoreError if that cannot be done or the user does not exist.
  let st = openStore(path, fragments, access)
  try:
    if st.db.scalar(int, "select count(*) from user") == 0:
      st.db.execute(
        "insert into user(name, is_default) values (:name, 1)", name = defaultUser
      )
    elif st.db.scalar(int, "select count(*) from user where is_default = 1") == 0:
      st.db.execute(
        "update user set is_default = 1 where id = (select min(id) from user)"
      )
    let id =
      if user.len == 0:
        st.db.queryOne(UserId, "select id from user where is_default = 1")
      else:
        st.db.queryOne(UserId, "select id from user where name = :name", name = user)
    if id.isNone:
      raiseStore("no such user: " & user)
    result = Session(
      store: st,
      db: st.db,
      path: st.path,
      userId: id.get,
      userName:
        st.db.scalar(string, "select name from user where id = :id", id = id.get),
    )
  except StoreError:
    close(st)
    raise

proc openSession*(g: Globals): Session {.raises: [StoreError].} =
  ## The database and the user the global options point at.
  openSession(resolveDbPath(g.dbPath), g.fragments, g.user, g.access)
