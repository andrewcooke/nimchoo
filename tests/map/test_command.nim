## `nch map` with a subject and frames that belong to no package (tests/support/testframes.nim): the map needs nothing of the
## packages above it.  The real frames are tested with their providers.

import std/[options, json, os, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/cache/cache
import nimchoo/packages/db/statement
import nimchoo/packages/map/command as mapCommand
import nimchoo/packages/user/session
import ../support/[env, testframes]
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-map"

proc world(name: string, selected = 2): tuple[db, cache: string] =
  ## A database with `selected` activities, all selected.
  removeDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache" / "user")
  putEnv("NCH_CACHE", dir / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  for i in 1 .. selected:
    s.db.execute(
      "insert into file(user_id, name, sha256, imported_epoch) values (:userId, :name, :name, 0)",
      userId = s.userId,
      name = "f" & $i,
    )
    s.db.execute(
      "insert into activity(file_id, session, start_epoch, end_epoch, riding_start_epoch, riding_end_epoch) select max(id), 0, :t, :t + 10, :t, :t + 10 from file",
      t = i * 1000,
    )
    s.db.execute(
      "insert into activity_selection(user_id, activity_id) select :userId, max(id) from activity",
      userId = s.userId,
    )

proc globals(db: string): Globals =
  Globals(
    dbPath: some(db),
    fragments: allFragments,
    access: allAccess,
    extensions: testExtensions(),
  )

proc run(db: string, args: varargs[string]): int =
  ## `nch map ARGS` as given (the command serves the page unless told `--file` or `--worker`).
  mapCommand.run(globals(db), @args)

proc files(cache: string): seq[string] =
  if dirExists(cache):
    for f in walkFiles(cache / "*"):
      result.add f.extractFilename

suite "map: the command, with frames of its own":
  test "by default the frames that are shown, a file for each, named for the subject and the frame":
    let w = world("basic")
    check run(w.db, "--file") == exitOk
    check files(w.cache) == @["map-things-alpha.geojson"]
    check isCacheFileName("map-things-alpha.geojson")
    check parseFile(w.cache / "map-things-alpha.geojson")["features"].len == 2
  test "the subject may be named, and the frames chosen: each once, in the order given":
    let w = world("choose")
    check run(w.db, "things", "--frames", "beta", "alpha", "beta", "--file") == exitOk
    check files(w.cache) == @["map-things-alpha.geojson", "map-things-beta.geojson"]
  test "a subject or a frame that is not there is a usage error that says what there is, and nothing is written":
    let w = world("unknown")
    check run(w.db, "nothing", "--file") == exitUsage
    check run(w.db, "--frames", "gamma", "--file") == exitUsage
    check run(w.db, "--frames", "alpha") == exitUsage # (on the page, the boxes choose)
    check run(w.db, "things", "--frames", "alpha", "gamma", "--file") == exitUsage
    check run(w.db, "a", "b", "--file") == exitUsage
    check run(w.db, "Things", "--file") == exitUsage
    check files(w.cache).len == 0
  test "a frame that fails stops the map with what it said":
    let w = world("broken")
    check run(w.db, "--frames", "alpha", "broken", "--file") == exitFailure
  test "an empty selection is said before anything is made (and before serving), and is no failure":
    let w = world("empty", selected = 0)
    check run(w.db, "--file") == exitOk
    check run(w.db) == exitOk # (serving: not started)
    check files(w.cache).len == 0
    # a page already served is made from the data as they are, empty or not
    check run(w.db, "--worker") == exitOk
  test "a map is made again from the data as they are, on every request":
    let w = world("live")
    check run(w.db, "--file") == exitOk
    let path = w.cache / "map-things-alpha.geojson"
    setLastModificationTime(path, fromUnix(1_000_000_000))
    let s = openSession(w.db, allFragments, access = allAccess)
    s.db.execute("delete from activity_selection where activity_id = 1")
    s.close()
    check run(w.db, "--file") == exitOk
    check getLastModificationTime(path).toUnix != 1_000_000_000
    check parseFile(path)["features"].len == 1
    check files(w.cache).len == 1
  test "--worker makes the page of the subject: every frame of it listed, with its style and drawing; no data":
    let w = world("worker")
    check run(w.db, "--worker") == exitOk
    check files(w.cache) == @["map-things.html"]
    let page = readFile(w.cache / "map-things.html")
    check page.contains("\"name\":\"alpha\"") and page.contains("\"name\":\"beta\"")
    check page.contains("\"style\":{\"color\":\"#e03131\"}") # (the style of a frame)
    check page.contains("\"drawer\":\"\"") # (alpha has no drawing: the generic one)
    check page.contains("drawers[\"test-map-beta\"] = (") # (beta has its own)
    check page.contains("\"shown\":true") # (alpha, shown by default)
    check "{{" notin page
  test "--worker --frame makes the data of that one frame, which the page fetches; a frame not of the subject is an error":
    let w = world("frame")
    check run(w.db, "--worker", "--frame", "beta") == exitOk
    check files(w.cache) == @["map-things-beta.geojson"]
    check run(w.db, "--worker", "--frame", "gamma") == exitUsage
    check run(w.db, "--worker", "--frame", "broken") == exitFailure
      # (it says what it said)
  test "the options go together as they should; the old ones are gone":
    let w = world("usage")
    check run(w.db, "--file", "--worker") == exitUsage
    check run(w.db, "--file", "--port", "0") == exitUsage
    check run(w.db, "--layers", "alpha", "--file") == exitUsage
    check run(w.db, "--selection", "AB") == exitUsage
    check run(w.db, "--web") == exitUsage
    check run(w.db, "--help") == exitOk
    check files(w.cache).len == 0
  test "a cache directory that cannot be made is an error":
    let w = world("blocked")
    writeFile(dir / "blocked" / "file", "")
    putEnv("NCH_CACHE", dir / "blocked" / "file" / "cache")
    check run(w.db, "--file") == exitFailure
    useTestCache()
