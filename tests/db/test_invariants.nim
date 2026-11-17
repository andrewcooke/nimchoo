## The invariants (tests/support/invariants.nim) hold of a good small database
## and are caught when broken.  (`nimble invariants` runs them over a real one.)

import nimchoo/packages/db/statement
import ../support/arrays
import nimchoo/packages/fit/time
import nimchoo/packages/importer/coord
import std/[os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/packages/db/store
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/geo/cells
import ../support/invariants

let dir = getTempDir() / "nch-test-invariants"

proc fresh(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  result = openSession(path, allFragments, access = allAccess)
  let db = result.db
  db.execute(
    "insert into file(id, user_id, name, sha256, imported_at) values (1, :userId, 'a', 'x', 0)",
    userId = int64(result.userId),
  )
  db.execute(
    "insert into activity(id, file_id, session, start_t, end_t, start_place) values (1, 1, 0, 1000, 2000, '')"
  )
  db.execute("insert into segment values (1, 0, 1000, 1500), (1, 1, 1600, 2000)")
  db.execute(
    "insert into sector(id, length_m, gain_m, gradient, name) values (1, 500, 40, 8, 'x')"
  )
  db.execute("insert into climbs_done values (1, 1)")

proc effort(db: DbConn, startT, finishT: int) =
  db.execute(
    "insert into effort values (1, 1, :startT, :finishT, :elapsedS, 0)",
    startT = startT,
    finishT = finishT,
    elapsedS = finishT - startT,
  )

suite "invariants":
  test "a good database violates none":
    let s = fresh("good")
    s.db.effort(1100, 1200)
    check violations(s.db) == newSeq[string]()
    s.close()

  test "an effort across a gap between stretches is found":
    let s = fresh("gap")
    s.db.effort(1400, 1700)
    let v = violations(s.db)
    check v.len == 1
    check v[0].startsWith("every effort lies within one stretch")
    s.close()

  test "overlapping segments, a missing climb decision and an orphan are found":
    let s = fresh("several")
    s.db.execute("update segment set start_t = 1400 where n = 1")
    s.db.execute(
      "insert into sector(id, length_m, gain_m, gradient) values (2, 500, 40, 8)"
    )
    s.db.execute("pragma foreign_keys = off")
    s.db.putHeart(99, @[(UnixTime(1000), 70)])
    let v = violations(s.db).join("\n")
    check "stretches of an activity are in order" in v
    check "every climb has a name decision" in v
    check "no foreign key points at nothing" in v
    s.close()

  test "visits that overlap, ones the positions do not give, and positions with no visits are found":
    let s = fresh("cells")
    let c = int64(cell(111974, 57907))
    s.db.putTrack(1, @[Coord(t: UnixTime(1000), lon: -70.65, lat: -33.45)])
    s.db.execute(
      "update activity set start = MakePoint(-70.65, -33.45, 4326) where id = 1"
    )
    check violations(s.db).join("\n").contains("exactly when it has positions")
    s.db.execute("insert into route_cell values (1, :c, 1000, 1000)", c = c)
    check violations(s.db) == newSeq[string]()
    s.db.execute("update route_cell set t_out = 1500")
    s.db.execute("insert into route_cell values (1, :c, 1400, 1600)", c = c)
      # (overlaps, and no sample at 1400)
    let v = violations(s.db).join("\n")
    check "visits of an activity to cells are in order and disjoint" in v
    check "are those of its stored positions" in v
    s.close()

  test "a climb with a route and no cells round its gates is found":
    let s = fresh("gates")
    s.db.execute(
      "insert into sector(id, length_m, gain_m, gradient, name, route) values (7, 500, 40, 8, 'y', GeomFromText('LINESTRING Z(-70.6 -33.4 10, -70.59 -33.39 50)', 4326))"
    )
    check violations(s.db) == newSeq[string]()
    s.db.execute("delete from sector_gate_cell where sector_id = 7 and which = 1")
    check violations(s.db).join("\n").contains(
      "every climb with a route has the cells round both its gates"
    )
    s.close()
