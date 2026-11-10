import ../../core/[extension, manifest]
import ../user/has
import ./[command, count]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(userHas, activityCount)]

const package* = Package(
  depends: @[
    "args", "bytes", "db", "download", "fit", "geo", "hashing", "names", "profiling",
    "ui", "user", "warnings",
  ],
  fragments: @[
    fragment("001-schema.sql"), # file, activity, coords, segment, route, seen_file
    fragment("002-seen-file-index.sql"),
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "put the activities of FIT files into the database, and name them",
      run: command.run,
    )
  ],
  contributes: contributions,
)
