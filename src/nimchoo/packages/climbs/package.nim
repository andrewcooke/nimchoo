import ../../core/manifest
import ./command

const package* = Package(
  depends: @[
    "args", "confirm", "db", "fit", "fold", "geo", "importer", "lookup", "names",
    "profiling", "selection", "ui", "user",
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
)
