import ../../core/[extension, manifest]
import ../activities/criterion
import ./[command, criterion]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(activityCriterion, climbCriterion)]

const package* = Package(
  depends: @[
    "activities", "args", "confirm", "db", "fit", "fold", "geo", "importer", "lookup",
    "names", "profiling", "selection", "ui", "user",
  ],
  fragments: @[
    fragment("001-schema.sql"), # sector (with retired), effort, climbs_done
    fragment("002-name-number.sql"), # sector.name_n
    fragment("003-effort-index.sql"), # effort(activity_id)
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the climbs of the selected activities, with times and ranks",
      run: command.run,
    )
  ],
  contributes: contributions,
)
