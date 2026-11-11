import std/[math, options, os, random, unittest]
import nimchoo/core/errors
import nimchoo/packages/db/[statement, store]
import nimchoo/packages/geo/cells
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

proc readOnlyDb(name: string): Store =
  ## A session that cannot write and has no SpatiaLite: the functions are ours, not its.
  let path = getTempDir() / "nch-test-functions" / name & ".db"
  createDir(parentDir(path))
  removeFile(path)
  openSession(path, allFragments, access = allAccess).close()
  openReadOnly(path, allFragments, allAccess)

suite "sql functions: the grid of cells":
  let s = readOnlyDb("cells")

  test "cell() is the one cell function: the same number as geo/cells, for any position":
    var r = initRand(20261112)
    for i in 0 ..< 300:
      let lon = r.rand(360.0) - 180.0
      let lat = r.rand(180.0) - 90.0
      check s.db.scalar(int64, "select cell(:lon, :lat)", lon = lon, lat = lat) ==
        int64(cellOf(lon, lat).get)
  test "and the formula of the design, written out in SQL, gives the same":
    # (the prototype of REVIEW.md §8 computed it so)
    for (lon, lat) in [
      (-70.65, -33.45), (-1.6, 54.1), (0.0, 0.0), (151.2, -33.9), (-180.0, -90.0)
    ]:
      check s.db.scalar(
        int,
        """select cell(:lon, :lat) = (cast(floor((:lat + 90) * 1024) as integer) << 32)
                                    | cast(floor((:lon + 180) * 1024) as integer)""",
        lon = lon,
        lat = lat,
      ) == 1
  test "a position that is not on the Earth, or a null, has no cell":
    check s.db.scalar(int, "select cell(181.0, 0.0) is null") == 1
    check s.db.scalar(int, "select cell(0.0, -90.5) is null") == 1
    check s.db.scalar(int, "select cell(null, 0.0) is null") == 1
    check s.db.scalar(int, "select cell(0.0, null) is null") == 1
  test "cell_coarse, cell_lon, cell_lat, cell_dx and cell_dy are those of geo/cells":
    var r = initRand(7)
    for i in 0 ..< 200:
      let c = cellOf(r.rand(300.0) - 150.0, r.rand(160.0) - 80.0).get
      let bits = r.rand(0 .. maxBits)
      let radius = r.rand(8000.0)
      check s.db.scalar(
        int64, "select cell_coarse(:c, :bits)", c = int64(c), bits = bits
      ) == int64(coarsen(c, bits))
      let k = coarsen(c, bits)
      let m = centre(k, bits)
      check s.db.scalar(float, "select cell_lon(:c, :bits)", c = int64(k), bits = bits) ==
        m.lon
      check s.db.scalar(float, "select cell_lat(:c, :bits)", c = int64(k), bits = bits) ==
        m.lat
      let steps = reach(k, bits, radius)
      check s.db.scalar(
        int, "select cell_dx(:c, :bits, :r)", c = int64(k), bits = bits, r = radius
      ) == steps.dx
      check s.db.scalar(
        int, "select cell_dy(:c, :bits, :r)", c = int64(k), bits = bits, r = radius
      ) == steps.dy
  test "the coarse cell of a position is the cell of the position at that level, in SQL alone":
    check s.db.scalar(
      int,
      "select cell_coarse(cell(-70.65, -33.45), 5) = cell_coarse(cell(-70.64, -33.46), 5)",
    ) == 1
    check s.db.scalar(
      int,
      "select cell_coarse(cell(-70.65, -33.45), 5) = cell_coarse(cell(-70.45, -33.45), 5)",
    ) == 0
  test "the steps for 2 km at the level of 1/32 degree: 1 at Santiago, 2 at 60 degrees":
    check s.db.scalar(
      int, "select cell_dx(cell_coarse(cell(-70.65, -33.45), 5), 5, 2000.0)"
    ) == 1
    check s.db.scalar(
      int, "select cell_dx(cell_coarse(cell(-1.6, 60.0), 5), 5, 2000.0)"
    ) == 2
  test "cell_shift steps east and north, and is null off the grid":
    var r = initRand(5)
    for i in 0 ..< 100:
      let c = cellOf(r.rand(300.0) - 150.0, r.rand(160.0) - 80.0).get
      let dx = r.rand(-8 .. 8)
      let dy = r.rand(-8 .. 8)
      check s.db.scalar(
        int64, "select cell_shift(:c, :dx, :dy)", c = int64(c), dx = dx, dy = dy
      ) == int64(shifted(c, dx, dy).get)
    check s.db.scalar(int, "select cell_shift(cell(-180.0, 0.0), -1, 0) is null") == 1
    check s.db.scalar(int, "select cell_shift(null, 1, 1) is null") == 1
  test "a null gives null":
    check s.db.scalar(int, "select cell_coarse(null, 5) is null") == 1
    check s.db.scalar(int, "select cell_lon(5, null) is null") == 1
    check s.db.scalar(int, "select cell_dx(5, 5, null) is null") == 1
  test "a level that does not exist, or a negative radius, is an error of the statement":
    expect StoreError:
      discard s.db.scalar(int, "select cell_coarse(5, 17)")
    expect StoreError:
      discard s.db.scalar(int, "select cell_lon(5, -1)")
    expect StoreError:
      discard s.db.scalar(int, "select cell_dy(5, 5, -1.0)")
