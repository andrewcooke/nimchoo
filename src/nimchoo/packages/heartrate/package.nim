import ../../core/[extension, manifest]
import ../importer/channel
import ./step

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, heartrateStep)]

const package* = Package(
  depends: @["db", "fit", "importer"],
  fragments: @[
    fragment("001-schema.sql") # heartrate
  ],
  contributes: contributions,
)
