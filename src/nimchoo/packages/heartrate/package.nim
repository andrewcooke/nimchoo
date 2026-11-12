## The heart-rate channel of an import.
##
## An import step (`importer/steps`): the `heart_rate` field of each record is kept as beats per minute, one reading per second
## at most, in the table `heartrate`.  `model` works the training impulse out of it.

import ../../core/[extension, manifest]
import ../importer/channel
import ./step

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, heartrateStep)]

const package* = Package(
  depends: @["db", "fit", "importer"],
  fragments: @[
    fragment("001-schema.sql"), # heartrate
    fragment("002-series.sql"), # heartrate_series: the same readings as arrays
  ],
  contributes: contributions,
)
