import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "confirm", "hashing", "proquint", "ui"],
  fragments: @[],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary:
        "the files outside the database (downloads, generated files): show them, delete them",
      run: command.run,
    )
  ],
)
