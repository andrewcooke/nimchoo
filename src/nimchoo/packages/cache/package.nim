## The cache directory: where files that commands make go, and what they are called.
##
## A command with a graphical result makes its file here (a GeoJSON file and a page for the map, CSV for `ff`), named after the
## request: the command and 48 bits of the hash of the request as proquints.  The request is written into the file
## (`nch.request`) and checked when the file is found, so a clash of names cannot show the wrong file; the key of everything
## else the file is made from is written too (`nch.inputs`), and if it differs the file is made again, in place.  The server
## (`web`) serves these files.  `nch cache` says what is there, by kind, and how big; `nch cache --delete KIND` deletes (no
## `-f`: everything in it can be made again).

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
      options: command.options,
    )
  ],
)
