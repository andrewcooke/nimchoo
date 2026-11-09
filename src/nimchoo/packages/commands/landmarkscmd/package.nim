import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @["args", "confirm", "db", "names", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "places of your own, named: they come before every other name",
      run: command.run,
    )
  ],
)
