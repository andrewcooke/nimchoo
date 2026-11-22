## `nch users`: the users, and what is known about each for training calculations (their
## functional threshold heart rate).  A user's name is the key for `--user`; `nch users`
## makes users (never implicitly, so a typo cannot), renames them and sets their FTHR.
##
## What else a user has (the activities, say) is said by the packages above this one, through the extension point
## `user/has`: each is a column of the list and a part of what a delete says it will remove.

import std/[options, strformat]
import ../../core/[extension, globals, ruled]
import ../db/statement
import ../db/store
import ../../core/errors
import ../../core/logfile
import ../confirm/confirm
import ../util/args/[args, usage]
import ./[has, params]
import ./users
import ./[profile, wipe]
import ./session
import ../ui/[units, vocabulary]

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
  intro = @[
    ~"Without options, show the users.  One user is always the default: the first, until another is made so.  (The users are named after the command, not by `--user` before it.)"
  ]
  notes = @[~"Names have 1 to 32 letters, digits and _ . - (not starting with -)."]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  usageOf(synopsis, width, intro, userSpec().docs, notes)

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

proc userLines*(
    st: Store, has: seq[UserHas], width: int
): seq[Line] {.raises: [StoreError].} =
  ## The users as a table (`core/ruled.nim`), one to a row: name, FTHR ("-" if not set), what the other packages say they
  ## have (`has`: how many activities, say), and "yes" for the default user.
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
      row.add count(h.count(st.db, UserId(r.id)))
    row.add (if r.isDefault: "yes" else: "")
    rows.add row
  header.add "default"
  var right: set[0 .. 31]
  for c in 1 ..< header.high:
    right.incl c
  ruled(header, rows, width, right = right)

proc userCount(st: Store): int {.raises: [StoreError].} =
  st.db.scalar(int, "select count(*) from user")

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch users ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch users", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch users", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  if g.user.len > 0:
    return usageError(
      g,
      "nch users",
      usageText(g.textWidth(osErr)),
      ~"`--user` goes after the command here: nch users `--edit` {g.user} ... (the users are named there)",
    )
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch users", e.msg)
  try:
    case p.action
    of uaList:
      g.showAll(osOut, userLines(st, g.extensions.get(userHas), g.textWidth(osOut)))
      g.done(listDone(userCount(st), none(int), "user", "users"))
      return exitOk
    of uaDelete:
      let id = findUser(st, p.delete.name)
      var has: seq[string]
      for h in g.extensions.get(userHas):
        has.add counted(h.count(st.db, id), h.one, h.heading)
      let what = describe(has, p.delete.name)
      if p.delete.force == fNo:
        return failure(
          g, "nch users", ~"would delete {what} from {st.path}; use `-f` to confirm"
        )
      pause(g.theme, what, p.delete.force)
      deleteUser(st, id)
      g.log.log(lvInfo, commandName, leDeleted, what & " from " & st.path)
      sayDeleted(g, "deleted " & what)
      return exitOk
    of uaAdd:
      let n = p.add
      if exists(st, n.name):
        return failure(g, "nch users", ~"there is a user called '{n.name}' already")
      var said = "made the user " & n.name
      st.writing(
        proc() {.closure, raises: [StoreError].} =
          addUser(st, n.name)
          let id = findUser(st, n.name)
          if n.makeDefault:
            setDefaultUser(st, id)
            said.add ", the default"
          if n.fthr.isSome:
            said.add ", with an FTHR of " & $n.fthr.get
            setFthr(st, id, n.fthr.get)
      )
      g.log.log(lvInfo, commandName, leSaved, said)
      g.done(plain(said))
      return exitOk
    of uaEdit:
      let e = p.edit
      let id = findUser(st, e.name)
      # everything that can refuse is asked first, and the changes are made together: all or none
      if e.rename.isSome and exists(st, e.rename.get):
        return
          failure(g, "nch users", ~"there is a user called '{e.rename.get}' already")
      var said: seq[string]
      st.writing(
        proc() {.closure, raises: [StoreError].} =
          case e.fthr.kind
          of fkSet:
            let old = currentFthr(st, id)
            setFthr(st, id, e.fthr.bpm)
            said.add fmt"{e.name}: FTHR is {e.fthr.bpm}" &
              (if old.isSome and old.get != e.fthr.bpm: recalculated else: "")
          of fkClear:
            let old = currentFthr(st, id)
            clearFthr(st, id)
            said.add fmt"{e.name}: FTHR forgotten" &
              (if old.isSome: recalculated else: "")
          of fkKeep:
            discard
          if e.makeDefault:
            setDefaultUser(st, id)
            said.add fmt"{e.name} is now the default user"
          if e.rename.isSome:
            renameUser(st, id, e.rename.get)
            said.add fmt"{e.name} is now called {e.rename.get}"
      )
      for line in said:
        g.log.log(lvInfo, commandName, leSaved, line)
        g.done(plain(line))
      return exitOk
  except StoreError as e:
    failure(g, "nch users", e.msg)
