## The channels of an activity: heart rate, cadence, temperature, power, speed and distance.
##
## An import step (`importer/steps`): for each channel of the list (`kinds.nim`, the one place a channel is described: its
## name, the record fields it is read from, its unit and how it is stored), the values of its fields, one reading per
## second at most, are kept as arrays (`series.nim`), a row of `channel_series` for each activity and channel it has.  A
## value outside a channel's stored range is dropped, with a warning.  `stored.nim` reads them back (`ff` works the
## training impulse out of the heart rate).  The speed and the distance are the device's (from a wheel, or its own from
## GPS), not worked out from the positions: dev/plot-activity.md says why.  A channel is added by adding it to the list
## (no fragment is needed); a channel that needs handling of its own can be a package of its own, as this one is.

import ../../core/[extension, manifest]
import ../importer/channel
import ./step

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, channelsStep)]

const package* = Package(
  depends: @["bytes", "db", "fit", "importer", "ui", "warnings"],
  fragments: @[
    fragment("001-schema.sql") # channel_series: the readings of each channel as arrays
  ],
  contributes: contributions,
)
