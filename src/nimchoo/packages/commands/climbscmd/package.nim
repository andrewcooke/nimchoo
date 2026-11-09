import ../../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "climbs", "confirm", "db", "names", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the climbs of the selected activities, with times and ranks",
      run: command.run,
    )
  ],
)
