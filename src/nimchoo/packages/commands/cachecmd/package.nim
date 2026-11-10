import ../../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "cache", "confirm", "ui"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary:
        "the files outside the database (downloads, generated files): show them, delete them",
      run: command.run,
    )
  ],
)
