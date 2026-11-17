## Putting the activities of FIT files into the database, and describing them.
##
## This package owns the tables `file`, `activity`, `track`, `segment`, `route`, `route_cell` and `seen_file`.  Per-second data is kept per
## activity, as arrays (`track`: the positions after the cleaning of `clean.nim`, encoded by `series.nim`; the heart rate is in `heartrate`); other data refers to it by time and never by array index, and the arrays are never changed once
## written.
##
## * **`nch import PATH...`.**  A path is a file or a directory searched for `*.fit` files (`walk.nim`: links to files and directories are followed, a directory is entered once, so a loop ends and a file reached twice is one).  A file whose path, size and
##   modification time are as when it was last seen is skipped unread (`--slow` reads everything); a file with content already
##   imported is a duplicate; a file that cannot be read is reported and the others carry on.  One transaction per file, files
##   decoded on several threads and written by one, in order.  What happened is written to the log in full, and shown on the
##   screen as two lines that follow the run.  The new activities are then named (`names`), and last the packages that asked
##   do their part.
## * **Extension points.**  `importer/steps`: what a package adds to the reading of each FIT file (`heartrate` writes the
##   heart rate), without the importer knowing about it.  `importer/after`: what a package does once an import has finished,
##   with the new activities (`selection` makes them the selection).
## * **Describing an activity** (decided 2026-11-05): an activity is said the same way wherever it appears, like `__str__`, by
##   `describe.nim`: `2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back` (start, sport, distance,
##   active time, then where it started and what it is called, joined by " / "); verbose adds the sub-sport and the path of
##   the file.  In a table the parts are cells, headed `start`, `sport`, `distance`, `active`, `place / name`; not recorded
##   is `-`, and an activity with no positions says `no GPS`.
## * **Where an activity went** (`route_cell`, decided 2026-11-12, dev/REVIEW.md "spatial data as cells"): one row for each visit
##   to a cell of the grid in `geo/cells.nim` (a run of consecutive samples in one cell, with its first and last time), so that
##   questions about places are joins on integers; `visits.nim` is the definition, written with the samples at import.
## * Deleting activities is `remove.nim`; `activities --delete` calls it.

import ../../core/[extension, manifest]
import ../user/has
import ./[after, channel, command, count]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(userHas, activityCount)]

const package* = Package(
  depends: @[
    "args", "bytes", "db", "download", "fit", "geo", "hashing", "names", "profiling",
    "ui", "user", "warnings",
  ],
  fragments: @[
    fragment("001-schema.sql"),
      # file, activity, coords, segment, route, seen_file, route_cell (the cells of the grid each activity went through)
    fragment("002-track.sql"), # track: the positions of an activity as arrays
    fragment("003-drop-coords.sql"), # (the rows of positions are gone)
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "put the activities of FIT files into the database, and name them",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: importStep.name,
      summary:
        "what packages add to the reading of each FIT file (the heart rate): the fields they want and where they write",
    ),
    PointDecl(
      name: afterImport.name,
      summary:
        "what packages do once an import has finished, with the new activities (the selection is made of them)",
    ),
  ],
  contributes: contributions,
)
