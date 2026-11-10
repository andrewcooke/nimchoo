## `nch users`: the users, and what is known about each for training calculations (their
## functional threshold heart rate).  A user's name is the key for `--user`; `nch users`
## makes users (never implicitly, so a typo cannot), renames them and sets their FTHR.
##
## What else a user has (the activities, say) is said by the packages above this one, through the extension point
## `user/has`: each is a column of the list and a part of what a delete says it will remove.

import std/[options, strformat, strutils]
import ../../core/[extension, globals]
import ../db/statement
import ../db/store
import ../../core/errors
import ../../core/logfile
import ../ui/live
import ../confirm/confirm
import ../util/args/[args, usage]
import ./[has, params]
import ./users
import ./[profile, wipe]
import ./session

{.push raises: [].}

const commandName* = "users" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch users`, described (for tab completion).
  userSpec().docs

const
  synopsis = """usage: nch users
       nch users --add NAME [--fthr BPM] [--default]
       nch users --edit NAME [--fthr BPM | --clear-fthr] [--rename NEW] [--default]
       nch users --delete NAME -f"""
  intro =
    """Without options, show the users.  One user is always the default: the first, until another is made so.  (The users
are named after the command, not by --user before it.)"""
  notes = "Names have 1 to 32 letters, digits and _ . - (not starting with -)."

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(userSpec().docs, width).join("\n") & "\n\n" & prose(notes, width) & "\n"

proc exists(st: Store, name: string): bool {.raises: [StoreError].} =
  st.db.scalar(int, "select count(*) from user where name = :name", name = name) != 0

const recalculated = " (what is worked out from the FTHR is worked out again)"
  ## said when the FTHR changes: the packages that work things out from it (`model`) do it again, by themselves

proc currentFthr(st: Store, id: UserId): Option[int] {.raises: [StoreError].} =
  let got = st.db.queryOne(
    Option[int], "select fthr from user_profile where user_id = :userId", userId = id
  )
  if got.isSome:
    got.get
  else:
    none(int)

func commas(n: int): string =
  insertSep($n, ',')

proc userLines*(st: Store, has: seq[UserHas]): seq[string] {.raises: [StoreError].} =
  ## The users, one to a line: name, FTHR ("-" if not set), what the other packages say they have (`has`: how many
  ## activities, say), and "yes" for the default user.
  var header = @["user", "fthr"]
  for h in has:
    header.add h.heading
  var rows: seq[seq[string]]
  for r in st.db.query(
    tuple[id: int64, name: string, fthr: Option[int], isDefault: bool],
    """select u.id, u.name, p.fthr, u.is_default
      from user u left join user_profile p on p.user_id = u.id order by u.name""",
  ):
    var row = @[r.name, (if r.fthr.isSome: $r.fthr.get else: "-")]
    for h in has:
      row.add commas(h.count(st.db, UserId(r.id)))
    row.add (if r.isDefault: "yes" else: "")
    rows.add row
  let last = header.len # (the flag column has the heading below, and is not aligned)
  var w = newSeq[int](last)
  for c in 0 ..< last:
    w[c] = header[c].len
    for r in rows:
      w[c] = max(w[c], r[c].len)
  proc line(cells: seq[string], flag: string): string =
    var parts = @[cells[0].alignLeft(w[0])]
    for c in 1 ..< last:
      parts.add cells[c].align(w[c])
    parts.add flag
    parts.join("  ").strip(leading = false)

  result.add line(header, "default")
  for r in rows:
    result.add line(r, r[last])

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch users ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch users", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  if g.user.len > 0:
    return usageError(
      "nch users",
      usageText(helpWidth(stderr)),
      "--user goes after the command here: nch users --edit " & g.user &
        " ... (the users are named there)",
    )
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch users", e.msg)
  try:
    case p.action
    of uaList:
      for l in userLines(st, g.extensions.get(userHas)):
        stdout.say l & "\n"
      return exitOk
    of uaDelete:
      let id = findUser(st, p.delete.name)
      var has: seq[string]
      for h in g.extensions.get(userHas):
        has.add counted(h.count(st.db, id), h.one, h.heading)
      let what = describe(has, p.delete.name)
      if not p.delete.force:
        return failure(
          "nch users",
          "would delete " & what & " from " & st.path & "; use -f to confirm",
        )
      if canLive():
        countdown(newTerminalLive(), what, waitSeconds, sleepMs)
      deleteUser(st, id)
      g.log.log(lvInfo, commandName, leDeleted, what & " from " & st.path)
      sayDeleted("deleted " & what)
      return exitOk
    of uaAdd:
      let n = p.add
      if exists(st, n.name):
        return failure("nch users", "there is a user called '" & n.name & "' already")
      addUser(st, n.name)
      let id = findUser(st, n.name)
      var said = "made the user " & n.name
      if n.makeDefault:
        setDefaultUser(st, id)
        said.add ", the default"
      if n.fthr.isSome:
        said.add ", with an FTHR of " & $n.fthr.get
        setFthr(st, id, n.fthr.get)
      g.log.log(lvInfo, commandName, leSaved, said)
      stdout.say said & "\n"
      return exitOk
    of uaEdit:
      let e = p.edit
      let id = findUser(st, e.name)
      case e.fthr.kind
      of fkSet:
        let old = currentFthr(st, id)
        setFthr(st, id, e.fthr.bpm)
        let said =
          fmt"{e.name}: FTHR is {e.fthr.bpm}" &
          (if old.isSome and old.get != e.fthr.bpm: recalculated else: "")
        g.log.log(lvInfo, commandName, leSaved, said)
        stdout.say said & "\n"
      of fkClear:
        let old = currentFthr(st, id)
        clearFthr(st, id)
        let said =
          fmt"{e.name}: FTHR forgotten" & (if old.isSome: recalculated else: "")
        g.log.log(lvInfo, commandName, leSaved, said)
        stdout.say said & "\n"
      of fkKeep:
        discard
      if e.makeDefault:
        setDefaultUser(st, id)
        let said = e.name & " is now the default user"
        g.log.log(lvInfo, commandName, leSaved, said)
        stdout.say said & "\n"
      if e.rename.isSome:
        if exists(st, e.rename.get):
          return failure(
            "nch users", "there is a user called '" & e.rename.get & "' already"
          )
        renameUser(st, id, e.rename.get)
        let said = e.name & " is now called " & e.rename.get
        g.log.log(lvInfo, commandName, leSaved, said)
        stdout.say said & "\n"
      return exitOk
  except StoreError as e:
    failure("nch users", e.msg)
