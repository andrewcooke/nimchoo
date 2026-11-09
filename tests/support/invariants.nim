## Statements that must hold of the data in any nimchoo database.  What the
## schema cannot say (a constraint over two tables, an order, a decision that
## must have been made) is written here as a query that finds the offenders.
## Used by tests/db/test_invariants.nim (small databases, including ones made
## to break them) and by tests/invariants.nim (`nimble invariants`: the
## author's own database, read only).

import std/[strutils]
import db_connector/db_sqlite
import nimchoo/db/statement

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
      "select cast(a.id as text) from activity a where exists (select 1 from coords c " &
      "where c.activity_id = a.id and (c.t < a.start_t or c.t > a.end_t))",
  ),
  Invariant(
    name: "an activity has a start point exactly when it has positions",
    offenders:
      "select cast(a.id as text) from activity a where (a.start is null) = " &
      "exists (select 1 from coords c where c.activity_id = a.id)",
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
      "(select 1 from coords c where c.activity_id = activity.id)",
  ),
  Invariant(
    name: "a climb has positive length and gain",
    offenders: "select cast(id as text) from sector where length_m <= 0 or gain_m <= 0",
  ),
  Invariant(
    name: "heart rates are plausible (1 to 250 bpm)",
    offenders:
      "select distinct cast(activity_id as text) from heartrate where bpm < 1 or bpm > 250",
  ),
  Invariant(
    name: "no foreign key points at nothing",
    offenders:
      "select \"table\" || ' row ' || ifnull(rowid, '(no rowid)') from pragma_foreign_key_check",
  ),
]

proc violations*(db: DbConn): seq[string] =
  ## One line per invariant that does not hold: its name, how many offenders,
  ## and the first few.
  for inv in allInvariants:
    let rows = db.query(string, inv.offenders & " limit 6")
    if rows.len > 0:
      let n = db.scalar(int, "select count(*) from (" & inv.offenders & ")")
      result.add inv.name & ": " & $n & " (" & rows[0 ..< min(rows.len, 5)].join(", ") &
        ")"
