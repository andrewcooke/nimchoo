import ../../core/[extension, package as corePackage]
import ../importer/channel
import ./step

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, heartrateStep)]

const package* = Package(
  depends: @["db", "fit", "importer"], fragments: @[], contributes: contributions
)
