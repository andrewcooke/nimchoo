import ../../core/[extension, manifest]
import ../importer/after
import ./imported

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(afterImport, selectNewActivities)]

const package* = Package(
  depends: @["db", "hashing", "importer", "ui", "user"],
  fragments: @[
    fragment("001-schema.sql"), # selection
    fragment("002-activity-index.sql"),
  ],
  contributes: contributions,
)
