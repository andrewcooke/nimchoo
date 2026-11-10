import ../../core/manifest
import ./command

const package* = Package(
  depends: @["activities", "args", "fit", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities of the selection on a calendar",
      run: command.run,
    )
  ],
)
