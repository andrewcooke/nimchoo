import std/[math, options, random, unittest]
import nimchoo/packages/geo/[cells, geo]

proc cellAt(lon, lat: float): Cell =
  cellOf(lon, lat).get

suite "cells: the grid":
  test "a cell is the two grid numbers, and gives them back":
    let c = cell(111974, 57907)
    check c.ix == 111974 and c.iy == 57907
    check int64(c) == ((57907'i64 shl 32) or 111974'i64)
    check cell(0xffffffff, 0xffffffff).ix == 0xffffffff
    check cell(0xffffffff, 0xffffffff).iy == 0xffffffff
  test "a position is in the cell of its floor, as in the design":
    # Santiago: (-70.65 + 180) * 1024 = 111974.4 and (-33.45 + 90) * 1024 = 57907.2
    let c = cellAt(-70.65, -33.45)
    check c.ix == 111974 and c.iy == 57907
    check cellAt(-180.0, -90.0) == cell(0, 0)
    check cellAt(0.0, 0.0) == cell(180 * 1024, 90 * 1024)
  test "a position that is not on the Earth has no cell":
    for (lon, lat) in [
      (NaN, 0.0),
      (0.0, NaN),
      (Inf, 0.0),
      (0.0, -Inf),
      (180.001, 0.0),
      (-180.001, 0.0),
      (0.0, 90.001),
      (0.0, -90.001),
    ]:
      check cellOf(lon, lat).isNone
    check cellOf(180.0, 90.0).isSome
      # (the edges are cells: the grid is one wider, not wrapped)
  test "the middle of a cell is in that cell, and a corner of the next is not":
    var r = initRand(11)
    for i in 0 ..< 500:
      let c = cellAt(r.rand(360.0) - 180.0, r.rand(179.0) - 89.5)
      let m = centre(c)
      check cellOf(m.lon, m.lat) == some(c)
    let c = cellAt(-70.65, -33.45)
    let m = centre(c)
    check abs((m.lon + 180.0) * 1024.0 - float(c.ix) - 0.5) < 1e-6
    check abs((m.lat + 90.0) * 1024.0 - float(c.iy) - 0.5) < 1e-6

suite "cells: coarser cells":
  test "coarsening shifts the two numbers, each by itself":
    let c = cellAt(-70.65, -33.45)
    check coarsen(c, 0) == c
    check coarsen(c, 5) == cell(c.ix shr 5, c.iy shr 5)
    check coarsen(c, 5) == cell(111974 div 32, 57907 div 32)
  test "shifting the whole integer is not coarsening (the bits of ix would move into iy)":
    let c = cellAt(-70.65, -33.45)
    check Cell(int64(c) shr 5) != coarsen(c, 5)
  test "cells of one coarse cell coarsen alike, and a coarse cell holds its fine ones":
    let c = cellAt(-70.65, -33.45)
    let k = coarsen(c, 5)
    for dx in 0 ..< 32:
      for dy in [0, 31]:
        check coarsen(cell((c.ix shr 5 shl 5) + dx, (c.iy shr 5 shl 5) + dy), 5) == k
    check coarsen(cell((c.ix shr 5 shl 5) + 32, c.iy), 5) != k
  test "the middle of a coarse cell is in it":
    let c = cellAt(-70.65, -33.45)
    for bits in [0, 1, 5, 10]:
      let m = centre(coarsen(c, bits), bits)
      check coarsen(cellAt(m.lon, m.lat), bits) == coarsen(c, bits)
  test "the levels are 0 to 16":
    expect AssertionDefect:
      discard coarsen(cell(1, 1), 17)
    expect AssertionDefect:
      discard coarsen(cell(1, 1), -1)

suite "cells: steps and sizes in metres":
  test "a cell is 109 m high everywhere, and as wide as that at the equator, half as wide at 60 degrees":
    check abs(cellHeightM() - 108.6) < 0.2
    check abs(cellWidthM(0.0) - cellHeightM()) < 1e-9
    check abs(cellWidthM(60.0) - cellHeightM() / 2) < 1e-6
    check abs(cellWidthM(-60.0) - cellWidthM(60.0)) < 1e-9
    check abs(cellWidthM(-33.45) - 90.7) < 0.2
    check cellHeightM(5) == 32 * cellHeightM()
  test "the neighbour is a step away, and there is none beyond the grid":
    let c = cell(10, 20)
    check shifted(c, 1, -2) == some(cell(11, 18))
    check shifted(cell(0, 5), -1, 0).isNone
    check shifted(cell(5, 0), 0, -1).isNone
    check shifted(cell(0xffffffff, 5), 1, 0).isNone
  test "2 km at the level of 1/32 degree: one cell round at Santiago, two at 60 degrees":
    let santiago = coarsen(cellAt(-70.65, -33.45), 5)
    check reach(santiago, 5, 2000.0) == (1, 1)
    let north = coarsen(cellAt(-1.6, 60.0), 5) # (a coarse cell 1.74 km wide)
    check reach(north, 5, 2000.0).dx == 2
    check reach(north, 5, 2000.0).dy == 1
  test "no radius: no steps, and a radius is not negative":
    check reach(cell(1, 1), 0, 0.0) == (0, 0)
    expect AssertionDefect:
      discard reach(cell(1, 1), 0, -1.0)

suite "cells: the reach is in metres, at every latitude":
  # (the class of bug: a fixed number of cells that covers 2 km near the equator and not at 60 degrees)
  test "every point within the radius of a point of the cell is in a cell within the reach":
    var r = initRand(20261112)
    for lat0 in [-80.0, -60.0, -33.45, 0.0, 33.0, 54.0, 55.0, 60.0, 70.0, 80.0]:
      for (bits, radius) in [(0, 150.0), (3, 500.0), (5, 2000.0), (7, 5000.0)]:
        for i in 0 ..< 60:
          let home =
            coarsen(cellAt(r.rand(300.0) - 150.0, lat0 + r.rand(0.2) - 0.1), bits)
          let steps = reach(home, bits, radius)
          # a point anywhere in the home cell, and another within the radius of it, in any direction
          let n = float(cellsPerDegree) / float(1 shl bits)
          let lon = (float(home.ix) + r.rand(1.0)) / n - 180.0
          let lat = (float(home.iy) + r.rand(1.0)) / n - 90.0
          let p = projection(lon, lat)
          let d = r.rand(radius)
          let a = r.rand(2 * PI)
          let q = unproject(p, XY(x: d * cos(a), y: d * sin(a)))
          let there = cellOf(q.lon, q.lat)
          if there.isNone:
            continue # (off the grid)
          let c = coarsen(there.get, bits)
          check abs(c.ix - home.ix) <= steps.dx
          check abs(c.iy - home.iy) <= steps.dy
  test "the reach grows with the latitude (the number of cells for the same radius)":
    var last = 0
    for lat in [0.0, 30.0, 55.0, 70.0, 80.0, 88.0]:
      let dx = reach(coarsen(cellAt(0.5, lat), 5), 5, 2000.0).dx
      check dx >= last
      last = dx
    check last > 2
