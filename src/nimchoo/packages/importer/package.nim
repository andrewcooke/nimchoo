import ../../core/[extension, manifest]
import ../user/has
import ./count

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(userHas, activityCount)]

const package* = Package(
  depends: @[
    "bytes", "db", "fit", "geo", "hashing", "names", "profiling", "ui", "user",
    "warnings",
  ],
  fragments: @[
    fragment("001-schema.sql"), # file, activity, coords, segment, route, seen_file
    fragment("002-seen-file-index.sql"),
  ],
  contributes: contributions,
)
