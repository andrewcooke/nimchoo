## `nch empty`: delete a user's data (the user stays), the whole database, or the files in the
## cache.  What to empty is named after the command: there is no default, since a command that
## deletes should not guess.  Does nothing without --force (except the cache, which is made
## again as needed); on a terminal it then counts down, in red, so there is time to press
## Ctrl-C.  (The deleting is in user/wipe.nim; `nch user --remove` shares it.)

import std/[options, os]
import ../cache
import ../cli/[args, common]
import ../climbs/work as climbsWork
import ../download/[fetch, sources]
import ../names/features as namesFeatures
import ../db/store
import ../errors
import ../ui/[live, logfile]
import ../user/wipe
import ./cachefiles

{.push raises: [].}

const usage* = """usage: nch [--db PATH] empty --user NAME -f
       nch [--db PATH] empty --all -f
       nch [--db PATH] empty --sectors -f
       nch [--db PATH] empty --names -f
       nch empty --cache

Say what to empty:

  --user NAME   delete all the data of the user NAME: their files, activities, selection and
                what was worked out from them.  The user, and their threshold heart rate,
                stay.  (To delete the user as well: `nch user --remove NAME -f`.)
  --sectors     delete the catalogue of climbs, and with it the efforts of every user on them;
                the next `nch climbs` works them out again from the rides
  --names       delete the place names and countries: their tables, and the GeoNames files downloaded
                for them (both are fetched again when wanted; the names already given to climbs stay)
  --all         delete the database file, and with it the data of every user and the users
  --cache       delete the files in the cache that commands made (maps, CSVs, pages); they
                are made again when asked for.  Needs no -f.

Nothing else is deleted without -f.  On a terminal there are then 5 seconds in
which to press Ctrl-C.

  -f, --force   really do it
  -h, --help    show this help
"""

type EmptyArgs = object
  user: string
  all, sectors, names, cache, force, help: bool

proc emptyCache(g: Globals): int =
  let dir = cacheDir()
  if dir.isNone:
    return failure("nch empty", "there is no cache directory (set NCH_CACHE, XDG_CACHE_HOME or HOME)")
  let what = describe(cacheFiles(dir.get))
  discard removeCacheFiles(dir.get)
  g.log.log(lvInfo, "empty", leDeleted, what & " from " & dir.get)
  stdout.say "done: deleted " & what & "\n"
  exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch empty ARGS`; returns the exit status.
  var given = EmptyArgs()
  let spec = Spec[EmptyArgs](opts: @[
    flag(EmptyArgs, ["-h", "--help"], help), flag(EmptyArgs, ["-f", "--force"], force),
    flag(EmptyArgs, ["--all"], all), flag(EmptyArgs, ["--sectors"], sectors),
    flag(EmptyArgs, ["--names"], names),
    flag(EmptyArgs, ["--cache"], cache),
    text(EmptyArgs, ["--user"], user)])
  let why = parseOptions(args, spec, given)
  if why.len > 0: return usageError("nch empty", usage, why)
  if given.help:
    stdout.say usage
    return exitOk
  if g.user.len > 0:
    return usageError("nch empty", usage,
      "--user goes after the command here: nch empty --user " & g.user & " (what to empty is named there)")
  let targets = [given.user.len > 0, given.all, given.sectors, given.names, given.cache]
  var named = 0
  for t in targets:
    if t: inc named
  if named == 0:
    return usageError("nch empty", usage, "say what to empty: --user NAME, --all, --sectors, --names or --cache")
  if named > 1:
    return usageError("nch empty", usage, "--user, --all, --sectors, --names and --cache cannot be used together")
  if given.cache: return emptyCache(g)
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    stdout.say "no database at " & path & ": nothing to empty\n"
    return exitOk
  var st: Store
  var id: UserId
  var what: string
  var namesDir = ""            # the downloaded files of the names (--names)
  if given.all:
    what = describe(countActivities(path, ""), "")
  elif given.sectors:
    try:
      st = openStore(g)
      what = describe(countClimbs(st))
    except StoreError as e:
      return failure("nch empty", e.msg)
  elif given.names:
    try:
      st = openStore(g)
      what = namesFeatures.describe(countNames(st))
    except StoreError as e:
      return failure("nch empty", e.msg)
    let cache = cacheDir()
    if cache.isSome:
      namesDir = sourceDir(dataDir(cache.get), geonamesCountry)
      let use = dataUsage(namesDir)
      what.add " and " & $use.files & (if use.files == 1: " downloaded file" else: " downloaded files") &
               " (" & humanBytes(use.bytes) & ")"
  else:
    try:
      st = openStore(g)
      id = findUser(st, given.user)         # (fails early for a user that does not exist)
    except StoreError as e:
      return failure("nch empty", e.msg)
    what = describeEmpty(countActivities(path, given.user), given.user)
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
  elif given.sectors:
    try:
      clearClimbs(st)
    except StoreError as e:
      return failure("nch empty", e.msg)
  elif given.names:
    try:
      clearNames(st)
    except StoreError as e:
      return failure("nch empty", e.msg)
    if namesDir.len > 0: discard clearData(namesDir)
  else:
    try:
      emptyUser(st, id)
    except StoreError as e:
      return failure("nch empty", e.msg)
  g.log.log(lvInfo, "empty", leDeleted, what & " from " & path)
  stdout.say "done: deleted " & what & "\n"
  exitOk
