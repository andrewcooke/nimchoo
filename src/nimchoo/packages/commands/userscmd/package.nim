import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @["args", "confirm", "db", "importer", "ui", "user", "model"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the users: make, rename, set the threshold heart rate",
      run: command.run,
    )
  ],
)
