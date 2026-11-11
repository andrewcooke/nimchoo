## The visits of an activity to the cells of the grid (geo/cells.nim): a visit is a run of consecutive samples in one cell,
## with the times of its first and last sample.  This is the definition of `route_cell`; the SQL that fills it for a
## database made before it (`004-route-cell-fill.sql`) says the same, and a test holds the two to it.  Pure.

import std/options
import ../fit/time
import ../geo/cells
import ./extract

{.push raises: [].}

type Visit* = object
  cell*: Cell
  tIn*, tOut*: UnixTime ## the first and the last sample in the cell

func visitsOf*(coords: openArray[Coord]): seq[Visit] =
  ## The visits of a route, in time order.  The samples are in time order; one with a position that is not on the Earth is
  ## left out, and the run goes on across it.
  for c in coords:
    let cell = cellOf(c.lon, c.lat)
    if cell.isNone:
      continue
    if result.len > 0 and result[^1].cell == cell.get:
      result[^1].tOut = c.t
    else:
      result.add Visit(cell: cell.get, tIn: c.t, tOut: c.t)
