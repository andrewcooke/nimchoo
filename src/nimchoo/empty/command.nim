## `nch empty`: delete all the data of a user (the user stays), or with `--all` delete the
## database.  Does nothing without --force; on a terminal it then counts down, in red, so there
## is time to press Ctrl-C.  (The deleting is in user/wipe.nim; `nch user --remove` shares it.)

import std/os
import ../cli/[args, common]
import ../db/store
import ../errors
import ../ui/[live, logfile]
import ../user/wipe

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] empty -f
       nch [--db PATH] empty --all -f

Delete all the data of the user (the default user, or the one given by --user): their files,
activities, selection and what was worked out from them.  The user, and their threshold heart
rate, stay.  (To delete the user as well: `nch --user NAME user --remove -f`.)

With --all: delete the database file, and with it the data of every user and the users.

Nothing is deleted without -f.  On a terminal there are then 5 seconds in
which to press Ctrl-C.

  -f, --force   really do it
  --all         the whole database, not one user's data
  -h, --help    show this help
"""

type EmptyArgs = object
  force, all, help: bool

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch empty ARGS`; returns the exit status.
  var given = EmptyArgs()
  let spec = Spec[EmptyArgs](opts: @[
    flag(EmptyArgs, ["-h", "--help"], help), flag(EmptyArgs, ["-f", "--force"], force),
    flag(EmptyArgs, ["--all"], all)])
  let why = parseOptions(args, spec, given)
  if why.len > 0: return usageError("nch empty", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  if given.all and g.user.len > 0:
    return usageError("nch empty", usage, "--all (the whole database) cannot be used with --user")
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    stdout.say "no database at " & path & ": nothing to empty\n"
    return exitOk
  var st: Store
  var what: string
  if given.all:
    what = describe(countActivities(path, ""), "")
  else:
    try:
      st = openStore(g)               # (fails early for a user that does not exist)
    except StoreError as e:
      return failure("nch empty", e.msg)
    what = describeEmpty(countActivities(path, st.userName), st.userName)
  if not given.force:
    return failure("nch empty", "would delete " & what & " from " & path & "; use -f to do it")
  if canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
  if given.all:
    try:
      for suffix in ["", "-journal", "-wal", "-shm"]:
        removeFile path & suffix
    except OSError as e:
      return failure("nch empty", "cannot delete " & path & ": " & e.msg)
  else:
    try:
      emptyUser(st)
    except StoreError as e:
      return failure("nch empty", e.msg)
  g.log.log(lvInfo, "empty", leDeleted, what & " from " & path)
  stdout.say "done: deleted " & what & "\n"
  exitOk
