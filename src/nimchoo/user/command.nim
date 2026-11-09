## `nch users`: the users, and what is known about each for training calculations (their
## functional threshold heart rate).  A user's name is the key for `--user`; `nch users`
## makes users (never implicitly, so a typo cannot), renames them and sets their FTHR.
##
## This module is newer than `importer` and `model`: it counts each user's activities and sees
## whether they have impulses.

import std/[options, strutils]
import ../cli/catalog
import ../core/globals
import ../db/[statement, store]
import ../core/errors
import ../core/logfile
import ../ui/live
import ./[params, wipe]

{.push raises: [].}

const usage* = """usage: nch users
       nch users --add NAME [--fthr BPM] [--default]
       nch users --edit NAME [--fthr BPM | --clear-fthr] [--rename NEW] [--default]
       nch users --delete NAME -f

Without options, show the users.  One user is always the default: the first, until
another is made so.  (The users are named after the command, not by --user before it.)

  --add NAME      make the user NAME (users are never made by accident: it must be asked for)
  --edit NAME     change the user NAME, with one or more of:
    --fthr BPM      the user's functional threshold heart rate: the highest rate they can
                    sustain for about an hour (80 to 230).  Heart-rate zones, and so training
                    impulse, are worked out from it.
    --clear-fthr    forget it
    --rename NEW    change the user's name
    --default       make the user the default: the one used when there is no --user
  --delete NAME   delete the user and everything they have (files, activities, ...); if
                  they were the default another user becomes it.  Needs -f; on a terminal
                  there are then 5 seconds in which to press Ctrl-C.  (To keep the user
                  and delete only their data: `nch activities --all --delete -f` with `--user NAME` before it.)
  -f, --force     really do it
  -h, --help      show this help

Names have 1 to 32 letters, digits and _ . - (not starting with -).
"""

proc exists(st: Store, name: string): bool {.raises: [StoreError].} =
  st.db.scalar(int, "select count(*) from user where name = :name", name = name) != 0

proc setFthr(st: Store, id: UserId, fthr: int) {.raises: [StoreError].} =
  st.db.execute(
    """insert into user_profile(user_id, fthr) values (:userId, :fthr)
      on conflict(user_id) do update set fthr = excluded.fthr""",
    userId = id,
    fthr = fthr,
  )

proc setDefault(st: Store, id: UserId) {.raises: [StoreError].} =
  ## Make `id` the default user (the old one stops being; both or neither).
  st.begin()
  try:
    st.db.execute("update user set is_default = 0 where is_default = 1")
    st.db.execute("update user set is_default = 1 where id = :id", id = id)
    st.commit()
  except StoreError:
    st.rollback()
    raise

const deletedNote = " (the impulses worked out with the old one are deleted)"

proc currentFthr(st: Store, id: UserId): Option[int] {.raises: [StoreError].} =
  let got = st.db.queryOne(
    Option[int], "select fthr from user_profile where user_id = :userId", userId = id
  )
  if got.isSome:
    got.get
  else:
    none(int)

proc hasImpulses(st: Store, id: UserId): bool {.raises: [StoreError].} =
  st.db.scalar(
    int,
    """select count(*) from impulse i join activity a on a.id = i.activity_id
      join file f on f.id = a.file_id where f.user_id = :userId""",
    userId = id,
  ) != 0

func commas(n: int): string =
  insertSep($n, ',')

proc userLines*(st: Store): seq[string] {.raises: [StoreError].} =
  ## The users, one to a line: name, FTHR ("-" if not set), how many activities they have, and
  ## "yes" for the default user.
  var rows: seq[array[4, string]]
  for r in st.db.query(
    tuple[name: string, fthr: Option[int], activities: int, isDefault: bool],
    """select u.name, p.fthr, (select count(*) from activity a
        join file f on f.id = a.file_id where f.user_id = u.id), u.is_default
        from user u left join user_profile p on p.user_id = u.id order by u.name""",
  ):
    rows.add [
      r.name,
      (if r.fthr.isSome: $r.fthr.get else: "-"),
      commas(r.activities),
      (if r.isDefault: "yes" else: ""),
    ]
  var w = [4, 4, 10]
  for r in rows:
    for c in 0 .. 2:
      w[c] = max(w[c], r[c].len)
  result.add (
    "user".alignLeft(w[0]) & "  " & "fthr".align(w[1]) & "  " & "activities".align(w[2]) &
    "  default"
  ).strip(leading = false)
  for r in rows:
    result.add (
      r[0].alignLeft(w[0]) & "  " & r[1].align(w[1]) & "  " & r[2].align(w[2]) & "  " &
      r[3]
    ).strip(leading = false)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch users ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch users", usage, p.problem)
  if g.user.len > 0:
    return usageError(
      "nch users",
      usage,
      "--user goes after the command here: nch users --edit " & g.user &
        " ... (the users are named there)",
    )
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch users", e.msg)
  try:
    if p.list:
      for l in userLines(st):
        stdout.say l & "\n"
      return exitOk
    if p.delete:
      let id = findUser(st, p.name)
      let what = describe(countActivities(st.path, p.name), p.name)
      if not p.force:
        return failure(
          "nch users",
          "would delete " & what & " from " & st.path & "; use -f to confirm",
        )
      if canLive():
        countdown(newTerminalLive(), what, waitSeconds, sleepMs)
      removeUser(st, id)
      g.log.log(lvInfo, $cmUsers, leDeleted, what & " from " & st.path)
      sayDeleted("deleted " & what)
      return exitOk
    if p.create:
      if exists(st, p.name):
        return failure("nch users", "there is a user called '" & p.name & "' already")
      st.db.execute("insert into user(name) values (:name)", name = p.name)
      let id = findUser(st, p.name)
      var said = "made the user " & p.name
      if p.makeDefault:
        setDefault(st, id)
        said.add ", the default"
      if p.fthr.isSome:
        said.add ", with an FTHR of " & $p.fthr.get
        setFthr(st, id, p.fthr.get)
      g.log.log(lvInfo, $cmUsers, leSaved, said)
      stdout.say said & "\n"
      return exitOk
    # --edit
    let id = findUser(st, p.name)
    if p.fthr.isSome:
      let had = hasImpulses(st, id)
      let old = currentFthr(st, id)
      setFthr(st, id, p.fthr.get)
      let said =
        p.name & ": FTHR is " & $p.fthr.get &
        (if had and old.isSome and old.get != p.fthr.get: deletedNote else: "")
      g.log.log(lvInfo, $cmUsers, leSaved, said)
      stdout.say said & "\n"
    if p.clearFthr:
      let had = hasImpulses(st, id)
      st.db.execute(
        "update user_profile set fthr = null where user_id = :userId", userId = id
      )
      let said =
        p.name & ": FTHR forgotten" &
        (if had: " (and the impulses worked out with it are deleted)" else: "")
      g.log.log(lvInfo, $cmUsers, leSaved, said)
      stdout.say said & "\n"
    if p.makeDefault:
      setDefault(st, id)
      let said = p.name & " is now the default user"
      g.log.log(lvInfo, $cmUsers, leSaved, said)
      stdout.say said & "\n"
    if p.rename.len > 0:
      if exists(st, p.rename):
        return failure("nch users", "there is a user called '" & p.rename & "' already")
      st.db.execute(
        "update user set name = :name where id = :id", name = p.rename, id = id
      )
      let said = p.name & " is now called " & p.rename
      g.log.log(lvInfo, $cmUsers, leSaved, said)
      stdout.say said & "\n"
    exitOk
  except StoreError as e:
    failure("nch users", e.msg)
