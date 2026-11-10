import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "confirm", "db", "ui"],
  fragments: @[
    fragment("001-schema.sql") # user, user_profile
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the users: make, rename, set the threshold heart rate",
      run: command.run,
    )
  ],
)
