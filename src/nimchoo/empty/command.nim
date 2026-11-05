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
       nch [--db PATH] empty --user NAME --sectors --names -f      (any of them together)

Say what to empty; several can be given at once, and are asked about, counted down and done together:

  --user NAME   delete all the data of the user NAME: their files, activities, selection and
                what was worked out from them.  The user, and their threshold heart rate,
                stay.  (To delete the user as well: `nch user --remove NAME -f`.)
  --sectors     delete the catalogue of climbs, and with it the efforts of every user on them;
                the next `nch climbs` works them out again from the rides.  Names given by hand
                (`nch sector --edit`) are lost; the message says how many
  --names       delete the place names and countries: their tables, and the GeoNames files downloaded
                for them (both are fetched again when wanted; the names already given to climbs stay)
  --all         delete the database file, and with it the data of every user and the users
  --cache       delete the files in the cache that commands made (maps, CSVs, pages); they
                are made again when asked for.  Needs no -f.

Nothing else is deleted without -f.  On a terminal there are then 5 seconds in
which to press Ctrl-C.  (--all stands alone, or with --names and --cache; it includes the rest.)

  -f, --force   really do it
  -h, --help    show this help
"""

type EmptyArgs = object
  user: string
  all, sectors, names, cache, force, help: bool

type Part = object
  ## One thing to empty: how to say it, and how to do it (it returns what went wrong, "" if nothing).
  what: string
  act: proc(): string {.closure, raises: [].}

func listed(parts: seq[Part]): string =
  ## The parts in one sentence, apart by semicolons ("167 activities of user bob; 43 sectors and 220 efforts").
  for i, p in parts:
    if i > 0: result.add "; "
    result.add p.what

proc emptyCache(g: Globals): int =
  ## The cache alone: it needs no -f, since the files are made again as needed.
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
  let wantUser = given.user.len > 0
  if not (wantUser or given.all or given.sectors or given.names or given.cache):
    return usageError("nch empty", usage, "say what to empty: --user NAME, --all, --sectors, --names or --cache")
  if given.all and (wantUser or given.sectors):
    return usageError("nch empty", usage,
      "--all deletes the whole database, which has the users' data and the climbs in it: give --all alone " &
      "(with --names or --cache for the downloaded and the generated files)")
  if given.cache and not (wantUser or given.all or given.sectors or given.names): return emptyCache(g)
  # what there is to empty, in the order it is done (the database file last)
  let cache = cacheDir()
  let path = resolveDbPath(g.dbPath)
  let haveDb = fileExists(path)
  if not haveDb and (wantUser or given.sectors or given.all):
    stdout.say "no database at " & path & ": nothing to empty there\n"
  var st: Store
  var parts: seq[Part]
  let tablesWanted = haveDb and not given.all and (wantUser or given.sectors or given.names)
  if tablesWanted:
    try:
      st = openStore(g)
    except StoreError as e:
      return failure("nch empty", e.msg)
  if wantUser and haveDb:
    var id: UserId
    try:
      id = findUser(st, given.user)           # (fails early for a user that does not exist)
    except StoreError as e:
      return failure("nch empty", e.msg)
    parts.add Part(what: describeEmpty(countActivities(path, given.user), given.user),
      act: proc(): string {.closure, raises: [].} =
        try: emptyUser(st, id)
        except StoreError as e: return e.msg)
  if given.sectors and haveDb:
    var what = ""
    try: what = describe(countClimbs(st))
    except StoreError as e: return failure("nch empty", e.msg)
    parts.add Part(what: what,
      act: proc(): string {.closure, raises: [].} =
        try: clearClimbs(st)
        except StoreError as e: return e.msg)
  if given.names:
    var what = ""
    var namesDir = ""
    if tablesWanted:
      try: what = namesFeatures.describe(countNames(st))
      except StoreError as e: return failure("nch empty", e.msg)
    if cache.isSome:
      namesDir = sourceDir(dataDir(cache.get), geonamesCountry)
      let use = dataUsage(namesDir)
      let files = $use.files & (if use.files == 1: " downloaded file" else: " downloaded files") &
                  " (" & humanBytes(use.bytes) & ")"
      what = (if what.len > 0: what & ", " & files else: files)
    if what.len > 0:
      parts.add Part(what: what,
        act: proc(): string {.closure, raises: [].} =
          if tablesWanted:
            try: clearNames(st)
            except StoreError as e: return e.msg
          if namesDir.len > 0: discard clearData(namesDir))
  if given.cache and cache.isSome:
    parts.add Part(what: describe(cacheFiles(cache.get)),
      act: proc(): string {.closure, raises: [].} =
        discard removeCacheFiles(cache.get))
  if given.all and haveDb:
    parts.add Part(what: describe(countActivities(path, ""), ""),
      act: proc(): string {.closure, raises: [].} =
        try:
          for suffix in ["", "-journal", "-wal", "-shm"]:
            removeFile path & suffix
        except OSError as e:
          return "cannot delete " & path & ": " & e.msg)
  if parts.len == 0: return exitOk
  let what = listed(parts)
  if not given.force:
    return failure("nch empty", "would delete " & what & "; use -f to confirm")
  if canLive():
    countdown(newTerminalLive(), what, waitSeconds, sleepMs)
  for p in parts:
    let problem = p.act()
    if problem.len > 0: return failure("nch empty", problem)
  g.log.log(lvInfo, "empty", leDeleted, what & (if haveDb: " from " & path else: ""))
  stdout.say "done: deleted " & what & "\n"
  exitOk
