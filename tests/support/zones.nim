## Time zones with a fixed offset, for tests that must not depend on the computer's zone.

import std/times

template fixedZone*(zoneName: string, east: int): Timezone =
  ## A timezone `east` seconds ahead of UTC (negative: behind).
  newTimezone(zoneName,
    proc (t: Time): ZonedTime {.tags: [], raises: [].} =
      ZonedTime(utcOffset: -east, isDst: false, time: t),
    proc (adj: Time): ZonedTime {.tags: [], raises: [].} =
      ZonedTime(utcOffset: -east, isDst: false, time: adj - initDuration(seconds = east)))
