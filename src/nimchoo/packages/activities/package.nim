import ../../core/manifest
import ./[command, criterion]

const package* = Package(
  depends:
    @["args", "confirm", "db", "fit", "fold", "importer", "selection", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
    )
  ],
  defines: @[
    PointDecl(
      name: activityCriterion.name,
      summary:
        "options that pick activities, offered to `nch activities` (`--climb`): a description and what it means as SQL",
    )
  ],
)
