## `nch user`: the users, and what is known about each for training calculations (their
## functional threshold heart rate).  A user's name is the key for `--user`; `nch user`
## makes users (never implicitly, so a typo cannot), renames them and sets their FTHR.
##
## This module is newer than `importer`: it counts each user's activities.

import std/[options, strutils]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ../ui/logfile
import ./params

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] user
       nch user NAME --create [--fthr BPM]
       nch [--db PATH] [--user NAME] user [--fthr BPM | --clear-fthr] [--rename NEW]

Without options, show the users.  Otherwise, make a user, or change the user given by
--user (the default user if there is none).

  --create        make the user NAME (users are never made by accident: it must be asked for)
  --fthr BPM      the user's functional threshold heart rate: the highest rate they can
                  sustain for about an hour (80 to 230).  Heart-rate zones, and so training
                  impulse, are worked out from it.
  --clear-fthr    forget it
  --rename NEW    change the user's name (not the default user's)
  -h, --help      show this help

Names have 1 to 32 letters, digits and _ . - (not starting with -).
"""

proc userId(st: Store, name: string): int64 {.raises: [StoreError].} =
  guard:
    let v = st.db.getValue(sql"select id from user where name = ?", name)
    if v.len == 0: raiseStore("no such user: " & name)
    try: result = parseBiggestInt(v)
    except ValueError: raiseStore("bad user id " & v)

proc exists(st: Store, name: string): bool {.raises: [StoreError].} =
  guard:
    result = st.db.getValue(sql"select count(*) from user where name = ?", name) != "0"

proc setFthr(st: Store, id: int64, fthr: int) {.raises: [StoreError].} =
  guard:
    st.db.exec(sql"""insert into user_profile(user_id, fthr) values (?, ?)
      on conflict(user_id) do update set fthr = excluded.fthr""", id, fthr)

func commas(n: string): string =
  try: insertSep($parseInt(n), ',') except ValueError: n

proc userLines*(st: Store): seq[string] {.raises: [StoreError].} =
  ## The users, one to a line: name, FTHR ("-" if not set), and how many activities they have.
  var rows: seq[array[3, string]]
  guard:
    for r in st.db.fastRows(sql"""select u.name, coalesce(p.fthr, ''), (select count(*) from activity a
        join file f on f.id = a.file_id where f.user_id = u.id)
        from user u left join user_profile p on p.user_id = u.id order by u.name"""):
      rows.add [r[0], (if r[1].len > 0: r[1] else: "-"), commas(r[2])]
  var w = [4, 4, 10]
  for r in rows:
    for c in 0 .. 2: w[c] = max(w[c], r[c].len)
  result.add "user".alignLeft(w[0]) & "  " & "fthr".align(w[1]) & "  " & "activities".align(w[2])
  for r in rows:
    result.add r[0].alignLeft(w[0]) & "  " & r[1].align(w[1]) & "  " & r[2].align(w[2])

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch user ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch user", usage, p.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch user", e.msg)
  defer: st.close()
  try:
    if p.list:
      for l in userLines(st): stdout.say l & "\n"
      return exitOk
    if p.create:
      if exists(st, p.name):
        return failure("nch user", "there is a user called '" & p.name & "' already")
      guard: st.db.exec(sql"insert into user(name) values (?)", p.name)
      var said = "made the user " & p.name
      if p.fthr.isSome:
        setFthr(st, userId(st, p.name), p.fthr.get)
        said.add ", with an FTHR of " & $p.fthr.get
      g.log.log(lvInfo, "user", leSaved, said)
      stdout.say said & "\n"
      return exitOk
    let id = st.userId
    if p.fthr.isSome:
      setFthr(st, id, p.fthr.get)
      let said = st.userName & ": FTHR is " & $p.fthr.get
      g.log.log(lvInfo, "user", leSaved, said)
      stdout.say said & "\n"
    if p.clearFthr:
      guard: st.db.exec(sql"update user_profile set fthr = null where user_id = ?", id)
      let said = st.userName & ": FTHR forgotten"
      g.log.log(lvInfo, "user", leSaved, said)
      stdout.say said & "\n"
    if p.rename.len > 0:
      if st.userName == defaultUser:
        return failure("nch user", "the default user cannot be renamed (it is made again whenever " &
                       "a database is opened)")
      if exists(st, p.rename):
        return failure("nch user", "there is a user called '" & p.rename & "' already")
      guard: st.db.exec(sql"update user set name = ? where id = ?", p.rename, id)
      let said = st.userName & " is now called " & p.rename
      g.log.log(lvInfo, "user", leSaved, said)
      stdout.say said & "\n"
    exitOk
  except StoreError as e:
    failure("nch user", e.msg)
