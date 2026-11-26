## The user whose data a command works on, and the database it works in: a `Session`.  `openSession` opens the
## database (`openStore`) and finds the user: the one asked for (`--user`), else the default.  A command that has a
## user starts with it; one that has none (the landmarks, which are everybody's) opens the `Store` alone.
##
## One user is the default (`user.is_default`): the one used when none is asked for.  A database with no users
## gets one, called `default`; if the default user has gone but others remain, the oldest of them becomes the
## default.
##
## A `Session` is used where a `Store` is (it converts), so only what needs the user says `Session`.

import std/[options, os]
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
  isDefault*: bool ## the user is the default one (used when none is asked for)

converter toStore*(s: Session): Store =
  s.store

proc close*(s: Session) {.raises: [].} =
  close(s.store)

proc lookupUser*(db: DbConn, name: string): Option[UserId] {.raises: [StoreError].} =
  ## The id of the user called `name`: the one place a user is looked up by name.
  db.queryOne(UserId, "select id from user where name = :name", name = name)

type UserSource* = enum ## where the user a command works for was named
  usOption = "--user"
  usEnvironment = "$NCH_USER"
  usDefault = "the database's default user"

proc openSession*(
    path: string,
    fragments: seq[Fragment],
    user = none(string),
    access: Access = nil,
    readOnly = false,
    named = usOption,
): Session {.raises: [StoreError].} =
  ## Open the database at `path` (as `openStore`) and find `user` (none: the default user, made if there are no
  ## users).  Raises StoreError if that cannot be done or the user does not exist (saying so names `$NCH_USER` if
  ## that is where the name came from, `named`).  With `readOnly` (as
  ## `openReadOnly`) nothing is made or changed: a database with no users, or no default, is an error.
  let st =
    if readOnly:
      openReadOnly(path, fragments, access)
    else:
      openStore(path, fragments, access)
  try:
    if readOnly:
      discard # (the users are as they are)
    elif st.db.scalar(int, "select count(*) from user") == 0:
      st.db.execute(
        "insert into user(name, is_default) values (:name, 1)", name = defaultUser
      )
    elif st.db.scalar(int, "select count(*) from user where is_default = 1") == 0:
      st.db.execute(
        "update user set is_default = 1 where id = (select min(id) from user)"
      )
    let id =
      if user.isNone:
        st.db.queryOne(UserId, "select id from user where is_default = 1")
      else:
        st.db.lookupUser(user.get)
    if id.isNone:
      raiseStore(
        if user.isNone:
          "the database has no default user"
        else:
          "no such user: " & user.get &
            (if named == usEnvironment: " (from $NCH_USER)" else: "")
      )
    result = Session(
      store: st,
      db: st.db,
      path: st.path,
      userId: id.get,
      userName:
        st.db.scalar(string, "select name from user where id = :id", id = id.get),
      isDefault:
        st.db.scalar(bool, "select is_default from user where id = :id", id = id.get),
    )
  except StoreError:
    close(st)
    raise

proc userAndSource*(
    option: Option[string]
): tuple[user: Option[string], source: UserSource] =
  ## The user to work for and where it was named: the `--user` option, else `$NCH_USER`, else none (the default user of
  ## the database).  The one place that decides (`nch --config` says the source too).  `$NCH_USER` is not `--user`: the
  ## commands that refuse `--user` before their name (`users`, `landmarks`) are not stopped by it.
  if option.isSome:
    return (option, usOption)
  let env = getEnv("NCH_USER")
  if env.len > 0:
    return (some(env), usEnvironment)
  (none(string), usDefault)

proc openSession*(g: Globals): Session {.raises: [StoreError].} =
  ## The database and the user the global options point at (`userAndSource`; read-only if they say so).
  let (user, source) = userAndSource(g.user)
  openSession(resolveDbPath(g.dbPath), g.fragments, user, g.access, g.readOnly, source)
