import std/[strutils, unittest]
import nimchoo/core/errors
import nimchoo/packages/activities/criterion
import nimchoo/packages/climbs/[criterion as climbsCriterion, work]
import nimchoo/packages/db/[sqltext, statement]
import nimchoo/packages/user/session
import nimchoo/packages/util/args/args
import ../support/climbdata

proc world(name: string): Session =
  let s = fresh(name)
  addRide(s, "default", "one", 1_000_000, 5.0, eastbound(5.0))
  discard ensureClimbs(s)
  s

suite "climbs: the criterion --climb offered to activities":
  test "it is described as an option that takes any number of words":
    let d = climbCriterion.doc
    check d.names == @["--climb"] and d.arity == aList and d.help.len > 0

  test "the words are alternatives, and commas separate them":
    let s = world("criterion-words")
    defer:
      s.close()
    let r = climbCriterion.resolve(s, @["unnamed", "unname,unnamed"])
    check r.condition.packages == @["climbs"]

  test "text that no climb has is an error, with what to do":
    let s = world("criterion-none")
    defer:
      s.close()
    expect StoreError:
      discard climbCriterion.resolve(s, @["no such climb zzz"])
    try:
      discard climbCriterion.resolve(s, @["no such climb zzz"])
    except StoreError as e:
      check "nch climbs --all" in e.msg

  test "the condition can be prepared by climbs alone, as a criterion over the activities":
    let s = world("criterion-alone")
    defer:
      s.close()
    let name = s.db.scalar(string, "select coalesce(name, '') from sector limit 1")
    let piece =
      climbCriterion.resolve(s, @[if name.len > 0: name else: "unnamed"]).condition
    let whole = sqlFrom("select a.id from activity a where ", "climbs") & piece
    discard prepareSql(s.db, whole, "climbs")
