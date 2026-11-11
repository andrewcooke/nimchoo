## The grid of cells that says where a ride went: latitude and longitude cut into cells of 1/1024 of a degree (about
## 109 m by 91 m at Santiago), each one an integer, so that questions about places are joins on integers.  A cell is
## `(iy << 32) | ix` with `ix = floor((lon + 180) * 1024)` and `iy = floor((lat + 90) * 1024)`.  Coarser cells (each
## `2^bits` finer ones across) are made from a fine one by `coarsen`, which shifts the two halves of the integer apart:
## **shifting the whole integer is wrong** (the bits of `ix` would move into `iy`).  The SQL functions that do the same are
## made from these (`db/functions.nim`), so that SQL and Nim cannot compute a cell differently.
##
## A plain latitude and longitude grid (the author's choice: nobody rides near the poles).  Its known limits, accepted: a
## cell gets narrower towards the poles, so a distance in metres is a different number of cells at each latitude (`reach`
## says how many), and cells either side of 180 degrees are not neighbours.  Pure.

import std/[math, options]
import ./geo

{.push raises: [].}

const
  cellsPerDegree* = 1024 ## the finest cells: `2^10` to a degree
  maxBits* = 16
    ## the coarsest level `coarsen` is asked for: cells of `2^16` finer ones across (64 degrees)
  maxLat = 89.99
    ## near the poles a cell has no width; `reach` works as if no nearer than this

type Cell* = distinct int64
  ## `(iy << 32) | ix`.  A coarsened cell is a cell too: whoever has one knows its `bits`.

func `==`*(a, b: Cell): bool {.borrow.}
func `$`*(c: Cell): string {.borrow.}

func cell*(ix, iy: int): Cell =
  ## The cell of the two grid numbers (each from 0 up to 2^32 - 1).
  Cell((int64(iy) shl 32) or int64(ix))

func ix*(c: Cell): int =
  ## The grid number east (0 at 180 degrees west).
  int(int64(c) and 0xffffffff'i64)

func iy*(c: Cell): int =
  ## The grid number north (0 at the south pole).
  int(uint64(c) shr 32)

func cellOf*(lon, lat: float): Option[Cell] =
  ## The cell of a position in degrees; none for one that is not on the Earth (not a number, or longitude outside -180 to
  ## 180, or latitude outside -90 to 90).
  if not (lon >= -180.0 and lon <= 180.0 and lat >= -90.0 and lat <= 90.0):
    return none(Cell)
  some(
    cell(
      int(floor((lon + 180.0) * cellsPerDegree)),
      int(floor((lat + 90.0) * cellsPerDegree)),
    )
  )

func coarsen*(c: Cell, bits: int): Cell =
  ## The cell `2^bits` finer ones across that holds `c` (the same cell for 0).
  doAssert bits in 0 .. maxBits, "a level from 0 to " & $maxBits
  cell(c.ix shr bits, c.iy shr bits)

func centre*(c: Cell, bits = 0): tuple[lon, lat: float] =
  ## The middle of a cell (or of a coarsened one, of `bits`), in degrees.
  let n = float(cellsPerDegree) / float(1 shl bits) # of these cells to a degree
  ((float(c.ix) + 0.5) / n - 180.0, (float(c.iy) + 0.5) / n - 90.0)

func shifted*(c: Cell, dx, dy: int): Option[Cell] =
  ## The cell `dx` east and `dy` north of `c` (of the same level), if that is on the grid.
  let x = c.ix + dx
  let y = c.iy + dy
  if x < 0 or y < 0 or x > 0xffffffff or y > 0xffffffff:
    return none(Cell)
  some(cell(x, y))

const metresPerDegree = earthRadius * PI / 180.0

func cellHeightM*(bits = 0): float =
  ## How far a cell of the level is from south to north, in metres (the same everywhere).
  metresPerDegree * float(1 shl bits) / float(cellsPerDegree)

func cellWidthM*(lat: float, bits = 0): float =
  ## How far a cell of the level is from west to east at the latitude, in metres.
  cellHeightM(bits) * cos(degToRad(min(abs(lat), maxLat)))

func reach*(c: Cell, bits: int, radiusM: float): tuple[dx, dy: int] =
  ## How many cells of the level (`c` is of it) to step either way in each direction, so that every cell within `radiusM`
  ## metres of any point of `c` is among those `dx` east or west and `dy` north or south of it.  The width of a cell is
  ## taken at the edge of `c` nearer a pole, where it is narrowest, so the answer is not too small anywhere in the cell
  ## (it is more than 1 near the poles, and the same cell asked at 60 degrees needs twice the steps of the equator).
  doAssert radiusM >= 0.0, "a radius is not negative"
  let n = float(cellsPerDegree) / float(1 shl bits)
  let south = float(c.iy) / n - 90.0
  let north = float(c.iy + 1) / n - 90.0
  let narrowest = cellWidthM(max(abs(south), abs(north)), bits)
  (int(ceil(radiusM / narrowest)), int(ceil(radiusM / cellHeightM(bits))))
