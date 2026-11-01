## `nch destroy`: delete the database, or (with --user) one user and everything
## that belongs to them.  Does nothing without --force; on a terminal it then
## counts down, in red, so there is time to press Ctrl-C.
##
## Everything belongs to a user through `on delete cascade`, so deleting the
## user row is enough.  This module is newer than `importer` and counts its
## activities; a later module that stores data adds a line to `describe`'s
## counts to be mentioned here (it is deleted either way).

import std/[options, os, strutils]
import db_connector/db_sqlite
import ../cli/common
import ../db/store
import ../errors
import ../ui/[live, logfile, style]

{.push raises: [].}

const
  usage* = """usage: nch [--db PATH] [--user NAME] destroy -f

Without --user: delete the database file, and with it the data of every user.
With --user NAME: delete that user and all their data (the default user is
created again, empty, the next time the database is opened).

Nothing is deleted without -f.  On a terminal there are then 5 seconds in
which to press Ctrl-C.

  -f, --force   really do it
  -h, --help    show this help
"""
  waitSeconds = 5

func activities(n: int): string =
  $n & (if n == 1: " activity" else: " activities")

func describe*(count: Option[int], user: string): string =
  ## What is to go: "74 activities for all users", "74 activities and user bob";
  ## "all data" if the count is not known.
  let items = if count.isSome: activities(count.get) else: "all data"
  if user.len == 0: items & " for all users" else: items & " and user " & user

func countdownLine*(what: string, seconds: int): Line =
  ## "deleting WHAT in 5 s ... (Ctrl-C to cancel)", in red.
  @[span("deleting " & what & " in ", cRed),
    span($seconds, cRed, bold = true),
    span(" s ... (Ctrl-C to cancel)", cRed)]

proc countdown*(l: Live, what: string, seconds: int,
                wait: proc(ms: int) {.closure, raises: [].}) =
  ## Show the line once a second, from `seconds` down to 1, then take it away.
  for s in countdown(seconds, 1):
    l.show @[countdownLine(what, s)]
    wait 1000
  l.finish()

proc sleepMs(ms: int) {.raises: [].} =
  try: sleep(ms)
  except OSError: discard

proc countActivities(g: Globals): Option[int] =
  ## How many activities there are (of the user, if given); none if the
  ## database cannot be opened, e.g. one from an older layout.
  var st: Store
  try:
    st = openStore(g)
  except StoreError:
    return none(int)
  defer: st.close()
  try:
    guard:
      let n = if g.user.len == 0:
                st.db.getValue(sql"select count(*) from activity")
              else:
                st.db.getValue(sql"select count(*) from activity where user_id = ?",
                               st.userId)
      result = some(parseInt(n))
  except StoreError, ValueError:
    result = none(int)

proc sizeOf(path: string): string =
  try: $getFileSize(path) & " bytes"
  except OSError: "unknown size"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch destroy ARGS`; returns the exit status.
  var force = false
  for a in args:
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-f", "--force"]:
      force = true
    else:
      return usageError("nch destroy", usage, "unexpected argument " & a)
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    stdout.say "no database at " & path & ": nothing to destroy\n"
    return exitOk
  if g.user.len > 0:                    # fail early for a user that does not exist
    var st: Store
    try:
      st = openStore(g)
    except StoreError as e:
      return failure("nch destroy", e.msg)
    st.close()
  let what = describe(countActivities(g), g.user)
  if not force:
    return failure("nch destroy", "would delete " & what & " from " & path &
      " (" & sizeOf(path) & "); use -f to do it")
  if canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
  if g.user.len == 0:
    try:
      for suffix in ["", "-journal", "-wal", "-shm"]:
        removeFile path & suffix
    except OSError as e:
      return failure("nch destroy", "cannot delete " & path & ": " & e.msg)
  else:
    var st: Store
    try:
      st = openStore(g)
    except StoreError as e:
      return failure("nch destroy", e.msg)
    defer: st.close()
    try:
      guard:
        st.db.exec(sql"delete from user where id = ?", st.userId)
        st.db.exec(sql"vacuum")
    except StoreError as e:
      return failure("nch destroy", e.msg)
  g.log.log(lvInfo, "destroy", "deleted " & what & " from " & path)
  stdout.say "deleted " & what & "\n"
  exitOk
