import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @["args", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "show the log, filtered, with the events coloured",
      run: command.run,
    )
  ],
)
