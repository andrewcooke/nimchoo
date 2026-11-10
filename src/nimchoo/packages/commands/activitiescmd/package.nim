import ../../../core/manifest
import ./command

const package* = Package(
  depends: @[
    "args", "climbs", "confirm", "db", "download", "fit", "fold", "importer", "names",
    "ui", "user", "warnings", "selection",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
    )
  ],
)
