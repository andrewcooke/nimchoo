import ../../core/[extension, manifest]
import ../web/request
import ./[command, web]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, ffPage(command.commandName))]

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
  contributes: contributions,
)
