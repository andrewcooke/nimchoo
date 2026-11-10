import ../../core/manifest
import ./command

const package* = Package(
  depends:
    @["args", "confirm", "db", "fit", "fold", "importer", "selection", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
    )
  ],
)
