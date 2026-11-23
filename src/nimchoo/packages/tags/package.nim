## Tags: small labels on activities ("bike:cotic", "sport:cycling:road"), to choose them by.
##
## The design and what was decided are in `dev/tags.md`.  This package holds the table and what a tag is:
##
## * **A tag** (`Tag`) is letters (accents too), digits, `-`, `_` and `:`, and does not start with `-` (it would read as an
##   option).  `key:value` is a convention only: nothing here reads it.  A **pattern** (`TagPattern`) may also hold `*`,
##   which matches anything (`bike:*`).
## * **Matching** ignores case and accents, as `--names` does: each tag is kept with its folded form (`fold`), and a
##   pattern is compared with that.  Two tags that fold the same are one tag on an activity (the first written is kept).
##   Several patterns are "and": an activity has a tag matching each (`tagsSql`).
## * **The table** `activity_tag` belongs to this package; tags go when their activity does.
## * **An import gives tags** (`step.nim`, an import step contributed to `importer/steps`): the sport, as
##   `sport:SPORT:SUB-SPORT` (`sport:cycling:road`), or `sport:SPORT` when the sub-sport is not recorded or "generic".
##
## `activities --tags` chooses activities by them, and shows them with `-v`.  More to come (`dev/tags.md`, TODO): tags from
## the path an import is given, and `nch tags` to see and change them.

import ../../core/[extension, manifest]
import ../importer/channel
import ./step

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, tagsStep)]

const package* = Package(
  depends: @["db", "fold", "importer", "warnings"],
  fragments: @[
    fragment("001-schema.sql") # activity_tag: the tags of the activities
  ],
  contributes: contributions,
)
