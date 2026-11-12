## Statements that must hold of the data in any nimchoo database.  What the
## schema cannot say (a constraint over two tables, an order, a decision that
## must have been made) is written here as a query that finds the offenders.
## Used by tests/db/test_invariants.nim (small databases, including ones made
## to break them) and by tests/invariants.nim (`nimble invariants`: the
## author's own database, read only).

import std/[strutils]
import db_connector/db_sqlite
import nimchoo/core/[errors, ids]
import nimchoo/packages/db/statement
import nimchoo/packages/heartrate/stored
import nimchoo/packages/importer/[track, visits]

type Invariant* = object
  name*: string
  offenders*: string
    ## a query that gives one row per offender (first column: what to show)

const allInvariants* = [
  Invariant(
    name: "every effort lies within one stretch of riding of its activity",
    offenders:
      "select e.activity_id || ' sector ' || e.sector_id || ' at ' || e.start_t from effort e " &
      "where not exists (select 1 from segment s where s.activity_id = e.activity_id " &
      "and s.start_t <= e.start_t and e.finish_t <= s.end_t)",
  ),
  Invariant(
    name: "an effort starts before it finishes, and elapsed is the difference",
    offenders:
      "select activity_id || ' sector ' || sector_id from effort " &
      "where finish_t <= start_t or abs(elapsed_s - (finish_t - start_t)) > 0.001",
  ),
  Invariant(
    name: "the stretches of an activity are in order and disjoint",
    offenders:
      "select a.activity_id || ' segment ' || a.n from segment a " &
      "left join segment b on b.activity_id = a.activity_id and b.n = a.n + 1 " &
      "where a.end_t < a.start_t or (b.n is not null and b.start_t < a.end_t)",
  ),
  Invariant(
    name: "the stretches of an activity lie within the activity",
    offenders:
      "select s.activity_id || ' segment ' || s.n from segment s join activity a on a.id = s.activity_id " &
      "where s.start_t < a.start_t or s.end_t > a.end_t",
  ),
  Invariant(
    name: "the positions of an activity lie within the activity",
    offenders:
      "select cast(a.id as text) from activity a where exists (select 1 from track t " &
      "where t.activity_id = a.id and (t.t0 < a.start_t or t.t1 > a.end_t))",
  ),
  Invariant(
    name: "an activity has a start point exactly when it has positions",
    offenders:
      "select cast(a.id as text) from activity a where (a.start is null) = " &
      "exists (select 1 from track t where t.activity_id = a.id)",
  ),
  Invariant(
    name: "the visits of an activity to cells are in order and disjoint",
    offenders:
      "select a.activity_id || ' at ' || a.t_in from route_cell a " &
      "where a.t_out < a.t_in or exists (select 1 from route_cell b where b.activity_id = a.activity_id " &
      "and b.t_in > a.t_in and b.t_in <= a.t_out)",
  ),
  Invariant(
    name: "an activity has visits to cells exactly when it has positions",
    offenders:
      "select cast(a.id as text) from activity a where exists (select 1 from track t " &
      "where t.activity_id = a.id) != exists (select 1 from route_cell r where r.activity_id = a.id)",
  ),
  Invariant(
    name: "every climb with a route has the cells round both its gates",
    offenders:
      "select cast(s.id as text) from sector s where s.route is not null and (" &
      "not exists (select 1 from sector_gate_cell g where g.sector_id = s.id and g.which = 0) or " &
      "not exists (select 1 from sector_gate_cell g where g.sector_id = s.id and g.which = 1))",
  ),
  Invariant(
    name: "an activity with efforts has been looked at for climbs",
    offenders:
      "select distinct cast(e.activity_id as text) from effort e " &
      "where e.activity_id not in (select activity_id from climbs_done)",
  ),
  Invariant(
    name: "every climb has a name decision (a name, or \"\")",
    offenders: "select cast(id as text) from sector where name is null",
  ),
  Invariant(
    name: "every activity with positions has a naming decision",
    offenders:
      "select cast(id as text) from activity where start_place is null and exists " &
      "(select 1 from track t where t.activity_id = activity.id)",
  ),
  Invariant(
    name: "a climb has positive length and gain",
    offenders: "select cast(id as text) from sector where length_m <= 0 or gain_m <= 0",
  ),
  Invariant(
    name: "no foreign key points at nothing",
    offenders:
      "select \"table\" || ' row ' || ifnull(rowid, '(no rowid)') from pragma_foreign_key_check",
  ),
]

proc arrayViolations(db: DbConn): seq[string] {.raises: [StoreError].} =
  ## The invariants that need the arrays decoded (SQL cannot read them).
  var badVisits, badHeart: seq[string]
  for id in db.query(int64, "select activity_id from track order by activity_id"):
    let expected = visitsOf(readPositions(db, ActivityId(id)))
    let stored = db.query(
      tuple[cell, tIn, tOut: int64],
      "select cell, t_in, t_out from route_cell where activity_id = :id order by t_in",
      id = id,
    )
    var same = expected.len == stored.len
    if same:
      for i, v in expected:
        same =
          same and int64(v.cell) == stored[i].cell and int64(v.tIn) == stored[i].tIn and
          int64(v.tOut) == stored[i].tOut
    if not same:
      badVisits.add $id
  for id in db.query(
    int64, "select activity_id from heartrate_series order by activity_id"
  ):
    for (_, bpm) in readReadings(db, ActivityId(id)):
      if bpm < 1 or bpm > 250:
        badHeart.add $id
        break
  if badVisits.len > 0:
    result.add "the visits of an activity to cells are those of its stored positions: " &
      $badVisits.len & " (" & badVisits[0 ..< min(badVisits.len, 5)].join(", ") & ")"
  if badHeart.len > 0:
    result.add "heart rates are plausible (1 to 250 bpm): " & $badHeart.len & " (" &
      badHeart[0 ..< min(badHeart.len, 5)].join(", ") & ")"

proc violations*(db: DbConn): seq[string] =
  ## One line per invariant that does not hold: its name, how many offenders,
  ## and the first few.
  for inv in allInvariants:
    let rows = db.query(string, inv.offenders & " limit 6")
    if rows.len > 0:
      let n = db.scalar(int, "select count(*) from (" & inv.offenders & ")")
      result.add inv.name & ": " & $n & " (" & rows[0 ..< min(rows.len, 5)].join(", ") &
        ")"
  result.add arrayViolations(db)
