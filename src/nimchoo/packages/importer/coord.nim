## One position of an activity: a second, where, and what the device measured besides (kept in its own module so that
## `extract` and `clean` can both use it).

import std/options
import ../fit/time

{.push raises: [].}

const semicircleDegrees* = 180.0 / 2147483648.0
  ## degrees per FIT semicircle (the unit the file stores a position in)

type Coord* = object
  t*: UnixTime
  lon*, lat*: float ## degrees
  alt*: Option[float] ## metres
  speed*: Option[float]
    ## metres a second, as the device measured it (from the Doppler shift, so reflections disturb it less than the position);
    ## used by the cleaning when the file has it, and not stored
