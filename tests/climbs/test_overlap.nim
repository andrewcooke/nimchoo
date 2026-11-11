import std/unittest
import nimchoo/packages/climbs/[match, overlap]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
import ../support/[climbdata, paths]

proc withRoutes(name: string, routes: openArray[Path]): Session =
  ## A database with these routes as sectors 1, 2, ... (no altitudes: 0).
  result = fresh(name)
  for r in routes:
    result.db.execute(
      "insert into sector(length_m, gain_m, gradient, route) values (1000, 100, 5, GeomFromText(:route, 4326))",
      route = lineStringText(r),
    )

suite "climbs: a climb found again":
  let old = pathOf([(0.0, 0.0), (2000.0, 0.0)], 10.0)
  let s = withRoutes("overlaprepeat", [old])
  proc again(route: Path): bool =
    s.isRepeat(route, [1'i64])

  test "the same place is a repeat, even a little off":
    check again(old)
    check again(pathOf([(0.0, 10.0), (2000.0, 10.0)], 10.0))
    check again(pathOf([(30.0, 0.0), (1990.0, 0.0)], 10.0))
  test "more than 25 m off is not":
    check not again(pathOf([(0.0, 40.0), (2000.0, 40.0)], 10.0))
    check not again(pathOf([(0.0, 5000.0), (2000.0, 5000.0)], 10.0))
  test "overlapping by more than half of each is a repeat; by half or less is not":
    check again(pathOf([(800.0, 0.0), (2800.0, 0.0)], 10.0)) # 60 % of each
    check again(pathOf([(900.0, 0.0), (2900.0, 0.0)], 10.0)) # 55 %
    check not again(pathOf([(1100.0, 0.0), (3100.0, 0.0)], 10.0)) # 45 %
    check not again(pathOf([(1500.0, 0.0), (3500.0, 0.0)], 10.0)) # 25 %
  test "a much longer climb that contains the old one is its own climb, and so is a short one inside it":
    check not again(pathOf([(-3000.0, 0.0), (5000.0, 0.0)], 10.0))
    check not again(pathOf([(500.0, 0.0), (800.0, 0.0)], 10.0))
  test "degenerate routes, and no stored climb to compare with, are never repeats":
    check not again(Path())
    check not s.isRepeat(old, [])
    check not s.isRepeat(old, [99'i64]) # (no such climb)
  test "only the climbs asked about count":
    let two =
      withRoutes("overlaptwo", [pathOf([(0.0, 5000.0), (2000.0, 5000.0)], 10.0), old])
    check not two.isRepeat(old, [1'i64])
    check two.isRepeat(old, [1'i64, 2'i64])

proc copies(routes: openArray[Path]): seq[tuple[a, b: int64]] =
  let s = withRoutes("overlapcopies", routes)
  defer:
    s.close()
  s.nearCopies

suite "climbs: near copies (the duplicates report)":
  let a = pathOf([(0.0, 0.0), (3000.0, 0.0)], 10.0)
  proc nearCopy(b: Path): bool =
    copies([a, b]).len == 1

  test "nearly the same stretch is a near copy; a stretch with a fifth or more outside is not":
    check nearCopy(a)
    check nearCopy(pathOf([(200.0, 0.0), (3200.0, 0.0)], 10.0)) # 7 % outside each way
    check nearCopy(pathOf([(0.0, 0.0), (2500.0, 0.0)], 10.0)) # 17 % of a outside
    check not nearCopy(pathOf([(700.0, 0.0), (3700.0, 0.0)], 10.0))
      # 23 % outside each way
    check not nearCopy(pathOf([(500.0, 0.0), (1500.0, 0.0)], 10.0))
      # a short climb inside a long one
  test "a chain of climbs that each overlap the next is not made of near copies":
    let b = pathOf([(1000.0, 0.0), (4000.0, 0.0)], 10.0) # 67 % of each in common with a
    let c = pathOf([(2000.0, 0.0), (5000.0, 0.0)], 10.0)
    check copies([a, b, c]).len == 0
  test "pairs come with the lower id first, in order":
    let near = pathOf([(100.0, 0.0), (3100.0, 0.0)], 10.0)
    let far = pathOf([(0.0, 9000.0), (3000.0, 9000.0)], 10.0)
    check copies([a, far, near, a]) == @[(1'i64, 3'i64), (1'i64, 4'i64), (3'i64, 4'i64)]
