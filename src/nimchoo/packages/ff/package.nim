import ../../core/manifest
import ./command

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "db", "model", "templating", "ui", "web",
    "importer", "user",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the fitness and fatigue curves, as CSV for plotting",
      run: command.run,
    )
  ],
)
