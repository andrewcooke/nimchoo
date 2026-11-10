## Names for places: GeoNames features, and the author's own landmarks.
##
## Climbs and activities are named from places near them.  The names come from GeoNames files downloaded on demand and read by
## one-degree cells into `feature` and `coverage`; every feature is kept and the rules choose.  A name is decided in the run
## that needs it, or the command stops with the reason (`DownloadError`); `--offline` answers "nothing" everywhere, and
## names stay "" for good.  Do not build lazy back-filling for a bad connection: the program needs the internet for names
## and says so.  This package owns `country`, `country_cell`, `country_cell_done`, `coverage`, `feature` and `landmark`.
##
## **Landmarks** (`nch landmarks`) are the author's own names for places, shared by all users, and come before every other
## name: a ride that turns round inside a landmark's circle is "<landmark> and back", a climb that tops out in it is called by
## it.  Suggestions are found from the features and the rides.

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "cache", "confirm", "db", "download", "fold", "geo", "ui", "zip"],
  fragments: @[
    fragment("001-schema.sql"), # country, coverage, feature
    fragment("002-country-cells.sql"), # country_cell, country_cell_done
    fragment("003-country-cell-index.sql"),
    fragment("004-landmark.sql"), # landmark: the author's own names for places
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "places of your own, named: they come before every other name",
      run: command.run,
      options: command.options,
    )
  ],
)
