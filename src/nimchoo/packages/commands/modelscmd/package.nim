import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @["args", "db", "model"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the models: sets of variables for the training impulse",
      run: command.run,
    )
  ],
)
