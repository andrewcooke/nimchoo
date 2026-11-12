## The activities: listing them, choosing the selection, and deleting.
##
## `nch activities` with no arguments shows the selection; with criteria (or `--all`) it searches all the activities, and
## `--select` keeps what is listed as the selection.  `--all` means everything, not just the selection.  Nothing is deleted
## without `-f` (it says what it would delete, with a countdown on a terminal).  Criteria belong to this command alone; the
## other views (`climbs`, `map`, `calendar`) take the selection.
##
## * **Criteria** (`criteria.nim`): the command line parsed into a `Criteria`, and the `Criteria` turned into SQL in one place
##   (`matchSql`), used to list, count and save.  `latest` and `previous` refer to an activity (the newest of those that meet
##   the other criteria; the one that was selected before).  `--invert` negates all of them taken together.
## * **The point `activities/criteria`**: a package may offer an option that picks activities (a `Criterion`: the option's
##   description, and `resolve`, which gives an SQL condition on the activity `a` and its file `f`).  `climbs` offers `--climbs`.
##   The offered options appear in `--help` and are parsed like the others; the SQL pieces carry the package that wrote them,
##   so this package may run a condition that reads tables it does not.
## * The table (`table.nim`) and its rows (`rows.nim`, which `calendar` uses too); the delete (`deleterun.nim`).

import ../../core/manifest
import ./[command, criterion]

const package* = Package(
  depends:
    @["args", "confirm", "db", "fit", "fold", "importer", "selection", "ui", "user"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: activityCriterion.name,
      summary:
        "options that pick activities, offered to `nch activities` (`--climbs`): a description and what it means as SQL",
    )
  ],
)
