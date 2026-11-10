import ../../core/manifest
import ./command

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "climbs", "db", "fit", "hashing", "importer",
    "selection", "templating", "ui", "user", "version", "web",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the routes of the selected activities and their climbs, on a map",
      run: command.run,
    )
  ],
)
