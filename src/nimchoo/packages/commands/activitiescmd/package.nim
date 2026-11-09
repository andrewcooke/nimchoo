import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @[
    "args", "climbs", "confirm", "db", "delete", "download", "fit", "fold", "importer",
    "names", "ui", "warnings", "selection",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
    )
  ],
)
