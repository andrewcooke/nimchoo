import ../../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "confirm", "db", "download", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the database file: where it is and how big, or delete it",
      run: command.run,
    )
  ],
)
