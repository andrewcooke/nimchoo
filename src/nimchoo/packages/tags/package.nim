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
## * **The sport is the `sport:` tag**, and nothing else (the importer keeps no column of it): `sport.nim` reads it, for
##   every command that shows an activity's sport.  The user may change it (`sport:cycling:gravel`).
##
## * **`nch tags`** (`command.nim`, `params.nim`, `found.nim`): the tags with how many activities have each; `--add`,
##   `--delete` (asks), `--rename` (a merge is said, and asked).  It follows the steps of `nch activities`, with tags in place
##   of activities: no criteria, the selection; `--names` a criterion over all the activities, `--within` over the selected.
##
## `activities --tags` chooses activities by them, and shows them with `-v`; an import gives them from the sport and from
## a template in its path (`importer/paths.nim`).

import ../../core/[extension, manifest]
import ../importer/channel
import ./[command, step]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(importStep, tagsStep)]

const package* = Package(
  depends: @["args", "db", "fold", "importer", "selection", "ui", "user", "warnings"],
  fragments: @[
    fragment("001-schema.sql") # activity_tag: the tags of the activities
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the tags of the activities: show them, add, remove and rename them",
      run: command.run,
      options: command.options,
    )
  ],
  contributes: contributions,
)
