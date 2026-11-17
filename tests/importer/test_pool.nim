## Importing with threads must give exactly what importing without them does: the same database
## (ids included), the same events in the same order.  The threads only read and decode.

import nimchoo/packages/db/statement
import std/[options, os, strutils, unittest]
import ../support/shims
from ../support/env import useTestCache
import nimchoo/packages/importer/batch
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess
import ../support/fitbuilder

const
  base = 900_000_000
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  multisport =
    "../choochoo/data/test/source/python-fitparse/activity-large-fenxi2-multisport.fit"

useTestCache()
  # (these tests make databases: they use the cache directory made for tests)

let dir = getTempDir() / "nch-test-pool"

proc fileFrom(path: string, data: seq[byte]) =
  createDir(parentDir(path))
  var s = newString(data.len)
  for i, x in data:
    s[i] = char(x)
  writeFile(path, s)

proc tiny(startAt: int, lat = 536870912): seq[byte] =
  ## A small activity: two positions, one session.
  fitFile(
    defn(0, 20, @[(253, 4, uint32T), (0, 4, sint32T), (1, 4, sint32T)]) & b(0) &
      le32(startAt) & le32(lat) & le32(-1073741824) & b(0) & le32(startAt + 1) &
      le32(lat + 1000) & le32(-1073741824) &
      defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T)]) & b(1) & le32(startAt + 1) &
      le32(startAt)
  )

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

proc removeDb(path: string) =
  ## A database and its write-ahead log files (a log left from an earlier run does not fit a new file).
  for suffix in ["", "-wal", "-shm", "-journal"]:
    removeFile(path & suffix)

proc count(s: Session, table: string): int =
  s.db.scalar(int, "select count(*) from " & table)

proc snapshot(s: Session): string =
  ## Everything the import wrote, as one text (the ids too).
  for q in [
    "select group_concat(id || ':' || name || ':' || sha256, ';') from (select * from file order by id)",
    "select group_concat(id || ':' || file_id || ':' || session || ':' || start_t || ':' || end_t || ':' || ifnull(sport, '') || ':' || ifnull(name, ''), ';') from (select * from activity order by id)",
    "select group_concat(activity_id || ':' || n || ':' || start_t || ':' || end_t, ';') from (select * from segment order by activity_id, n)",
    "select group_concat(activity_id || ':' || t0 || ':' || t1 || ':' || n || ':' || hex(t) || hex(lon) || hex(lat) || hex(alt), ';') from (select * from track order by activity_id)",
    "select group_concat(activity_id || ':' || t0 || ':' || n || ':' || hex(t) || hex(bpm), ';') from (select * from heartrate_series order by activity_id)",
    "select group_concat(activity_id || ':' || hex(geom), ';') from (select * from route order by activity_id)",
    "select group_concat(path || ':' || size || ':' || ifnull(file_id, '') || ':' || ifnull(failure, '') || ':' || ifnull(message, ''), ';') from (select * from seen_file order by path)",
  ]:
    result.add s.db.scalar(Option[string], q).get("") & "\n"

type Run = tuple[lines: seq[string], snap: string, imported, duplicates, failed: int]

proc run(d: string, jobs: int, name: string): Run =
  ## Import everything under `d` into a database of its own, with this many threads.
  removeDb(dir / name & ".db")
  let st = openSession(dir / name & ".db", allFragments, access = allAccess)
  defer:
    st.close()
  let r = importReport(st, @[d], ImportOptions(quiet: false, jobs: jobs))
  (r.lines, snapshot(st), r.imported, r.duplicates, r.failed)

proc same(d: string, name: string, jobs: seq[int]) =
  ## The runs with the given numbers of threads give one result.
  let one = run(d, 1, name & "-1")
  for j in jobs:
    let many = run(d, j, name & "-" & $j)
    check many.lines == one.lines
    check many.snap == one.snap

suite "import with threads: the same as without":
  test "many small files, a window of them in flight at a time":
    let d = fresh("many")
    for i in 0 ..< 60:
      fileFrom(
        d / ("f" & align($i, 3, '0') & ".fit"),
        tiny(base + i * 1000, 536870912 + i * 5000),
      )
    same(d, "many", @[2, 4, 8])
    check run(d, 4, "many-x").imported == 60

  test "real files, several sessions, files of different sizes":
    let d = fresh("real")
    copyFile(ride, d / "a-ride.fit")
    copyFile(multisport, d / "b-multi.fit")
    for i in 0 ..< 12:
      fileFrom(d / ("c" & $i & ".fit"), tiny(base + i * 1000, 536870912 + i * 4000))
    same(d, "real", @[3, 4])
    let r = run(d, 4, "real-x")
    check r.imported == 14 and r.failed == 0

  test "the same content twice, in one run, under two names: one imported, one duplicate":
    let d = fresh("dups")
    fileFrom(d / "a.fit", tiny(base + 1))
    fileFrom(d / "b.fit", tiny(base + 1))
    fileFrom(d / "c.fit", tiny(base + 2, 536870912 + 99))
    fileFrom(d / "d.fit", tiny(base + 1))
    same(d, "dups", @[2, 4])
    let r = run(d, 4, "dups-x")
    check r.imported == 2 and r.duplicates == 2

  test "bad files in the middle: each is reported where it is, the others carry on":
    let d = fresh("bad")
    for i in 0 ..< 12:
      if i == 3:
        writeFile(d / ("f" & align($i, 2, '0') & ".fit"), "this is not a FIT file")
      elif i == 6:
        fileFrom(
          d / ("f" & align($i, 2, '0') & ".fit"),
          fitFile(defn(0, 20, @[(253, 4, uint32T)]) & b(0) & le32(base)),
        ) # no activity
      else:
        fileFrom(
          d / ("f" & align($i, 2, '0') & ".fit"),
          tiny(base + i * 1000, 536870912 + i * 3000),
        )
    same(d, "bad", @[2, 4])
    let r = run(d, 4, "bad-x")
    check r.imported == 10 and r.failed == 2
    check r.lines[3].contains("f03.fit") and r.lines[3].startsWith("failed")

  test "a file that cannot be read":
    let d = fresh("unreadable")
    for i in 0 ..< 6:
      fileFrom(d / ("f" & $i & ".fit"), tiny(base + i * 1000, 536870912 + i * 2000))
    setFilePermissions(d / "f2.fit", {})
    defer:
      setFilePermissions(d / "f2.fit", {fpUserRead, fpUserWrite})
    same(d, "unreadable", @[4])

  test "more threads than files, and one file that needs work":
    let d = fresh("few")
    fileFrom(d / "a.fit", tiny(base + 1))
    fileFrom(d / "b.fit", tiny(base + 2, 536870912 + 77))
    same(d, "few", @[8, 16])
    let one = fresh("one")
    fileFrom(one / "a.fit", tiny(base + 1))
    same(one, "one", @[8])

  test "a second run skips what was imported, with any number of threads":
    let d = fresh("again")
    for i in 0 ..< 20:
      fileFrom(d / ("f" & $i & ".fit"), tiny(base + i * 1000, 536870912 + i * 1500))
    removeDb(dir / "again.db")
    let st = openSession(dir / "again.db", allFragments, access = allAccess)
    defer:
      st.close()
    check importReport(st, @[d], ImportOptions(jobs: 4)).imported == 20
    let r = importReport(st, @[d], ImportOptions(jobs: 4))
    check r.unchanged == 20 and r.imported == 0
    check importReport(st, @[d], ImportOptions(jobs: 4, slow: true)).duplicates == 20
      # read again: found by content
    check st.count("activity") == 20

  test "a file removed after the files were found is reported, not a crash":
    let d = fresh("gone")
    for i in 0 ..< 4:
      fileFrom(d / ("f" & $i & ".fit"), tiny(base + i * 1000, 536870912 + i * 2000))
    # (the same listing, then a missing file: the batch finds the files first, so remove one from the list's reach)
    removeDb(dir / "gone.db")
    let st = openSession(dir / "gone.db", allFragments, access = allAccess)
    defer:
      st.close()
    let r = importReport(
      st, @[d / "f0.fit", d / "f1.fit", d / "nope.fit"], ImportOptions(jobs: 4)
    )
    check r.imported == 2 and r.failed == 1
