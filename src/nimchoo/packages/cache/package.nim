## The cache directory: where files that commands make go, and what they are called.
##
## A command with a graphical result makes its file here (a GeoJSON file and a page for the map, CSV for `ff`), named by the
## command and its options spelt out (`map-activities-routes.geojson`) and made again on every request: a file is never
## "current", it is what the last request made.  The server
## (`web`) serves these files.  `nch cache` says what is there, by kind, and how big; `nch cache --delete KIND` deletes (it asks
## first, as every delete does; everything in it can be made again).

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "ui"],
  fragments: @[],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary:
        "the files outside the database (downloads, generated files): show them, delete them",
      run: command.run,
      options: command.options,
    )
  ],
)
