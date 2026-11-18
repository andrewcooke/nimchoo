## The activities: listing them, choosing the selection, and deleting.
##
## `nch activities` with no arguments shows the selection; with criteria (or `--all`) it searches all the activities, and
## `--select` keeps what is listed as the selection.  **The selection's style (`select`) is the selection after the command**: the selection, all of it;
## `--all`, the selected ones among them; `--select`, everything listed; criteria alone change nothing, so none.  `--all` means everything, not just the selection.  Nothing is deleted
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
## * **A subject** (`subject.nim`): contributes the activities to `subject/subjects`, as the default, with how many the user's
##   selection holds.
## * **Map frames** (`mapframes.nim`): the routes of the selected activities and the heat (how often each place was visited), offered to
##   `map/frames` with the style of each.
## * **A calendar frame** (`calendarframe.nim`): the days of the selected activities and the line that sums them up, offered to
##   `calendar/frames`.
## * The table (`table.nim`) and its rows (`rows.nim`); the delete (`deleterun.nim`).

import ../../core/[extension, manifest]
import ./[calendarframe, command, criterion, mapframes, subject]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[subject.contribution(), calendarframe.contribution()] & mapframes.contributions()

const package* = Package(
  depends: @[
    "args", "bundle", "calendar", "confirm", "db", "fit", "fold", "geo", "importer",
    "map", "names", "selection", "subject", "ui", "user",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the activities: show them, choose the ones other commands use",
      run: command.run,
      options: command.options,
    )
  ],
  contributes: contributions,
  defines: @[
    PointDecl(
      name: activityCriterion.name,
      summary:
        "options that pick activities, offered to `nch activities` (`--climbs`): a description and what it means as SQL",
    )
  ],
)
