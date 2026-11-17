## The cache directory: where files that commands make go, and what they are called.
##
## A command with a graphical result makes its file here (a GeoJSON file and a page for the map, CSV for `ff`), named by the
## command and its options spelt out (`ff-default-hourly.csv`) and made again on every request: a file is never
## "current", it is what the last request made.  The files of a map also carry a key of what they were made from
## (`map-activities-routes-3f9a0c1d5e7b2a46.geojson`), so that two requests with different data do not share a name, and a
## file is never changed under a page that is loading it: they pile up, a file for each state of the data, until
## `nch cache --delete geojson html`.  The server
## (`web`) serves these files.  `nch cache` says what is there, by kind, and how big; `nch cache --delete KIND` deletes (no
## `-f`: everything in it can be made again).

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "confirm", "ui"],
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
