import ../../core/[extension, manifest]
import ../user/has
import ./[after, channel, command, count]

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
  defines: @[
    PointDecl(
      name: importStep.name,
      summary:
        "what packages add to the reading of each FIT file (the heart rate): the fields they want and where they write",
    ),
    PointDecl(
      name: afterImport.name,
      summary:
        "what packages do once an import has finished, with the new activities (the selection is made of them)",
    ),
  ],
  contributes: contributions,
)
