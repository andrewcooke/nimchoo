## The selection: the activities that commands work on unless told otherwise.
##
## It is what `climbs`, `map`, `calendar` and the like use.
##
## * **The selection** is a scratchpad in the database (table `selection`).  It belongs to one user; it is replaced whenever
##   `activities --select` is given (by what is listed: with `--also` the selection is added to it, with `--within` only
##   the selection was searched) or an import adds activities.  A view shows the selection as it is when the view is made.
## * Contributes to `importer/after`: after an import the new activities become the selection (if there are none, it stays).

import ../../core/[extension, manifest]
import ../importer/after
import ./imported

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(afterImport, selectNewActivities)]

const package* = Package(
  depends: @["db", "importer", "ui", "user"],
  fragments: @[
    fragment("001-schema.sql") # selection
  ],
  contributes: contributions,
)
