## The selection (the activities commands use by default) and the addresses that name a set.
##
## * **The selection** is a scratchpad in the database (table `selection`): the activities that `climbs`, `map`, `calendar` and
##   the like work on unless told otherwise.  It belongs to one user, and is replaced whenever `activities --select` is given
##   or an import adds activities.  This is implicit state, which conflicts with the caching of files made by commands, so the
##   state of the activities selected goes into the address of the plot made from them, and the plot is named by a hash of that.
## * **The address** (`selection`): a set of activity ids as a short string (runs or a bitmap, bit-level codes, URL-safe base64: one
##   ride is 5 characters, a date range 5 to 8), so `/map?selection=LIST&state=HASH` names its activities.  `HASH` is the state of the data
##   the plot is made from, which includes the content key of those activities (`contentKey`): after a database rebuild the ids
##   mean other activities, and the state refuses the old address.  **`--state` means check**: verification, never choice.
## * Contributes to `importer/after`: after an import the new activities become the selection (if there are none, it stays).

import ../../core/[extension, manifest]
import ../importer/after
import ./imported

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(afterImport, selectNewActivities)]

const package* = Package(
  depends: @["db", "hashing", "importer", "ui", "user"],
  fragments: @[
    fragment("001-schema.sql"), # selection
    fragment("002-activity-index.sql"),
  ],
  contributes: contributions,
)
