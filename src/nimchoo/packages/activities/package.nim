## The activities: listing them, choosing the selection, and deleting.
##
## `nch activities` with no arguments shows the selection; with criteria (or `--all`), what is listed is found in the steps
## the usage numbers (`nch activities -h`: written once, there).  **The selection's style (`select`) marks the activities listed that are
## in the selection after the command.**  `--all` means everything, not just the selection.  Nothing is deleted
## without an answer yes (`core/ask`: the question says what would be deleted; `-y` answers it).  Criteria belong to this command alone; the
## other views (`climbs`, `map`, `calendar`) take the selection.
##
## * **A request** (`request.nim`): what the command line asks, as a value that cannot say what means nothing: an action (list, delete,
##   rename) on a scope (the selection, every activity, those that match filters, with an optional newest or oldest limit).  A
##   `Filter` is a criterion as typed (it may refer to `latest` or `previous`); resolving it (`command.nim`) gives a `Resolved` one.
## * **Criteria** (`criteria.nim`): the command line parsed into a `Request`, and the `Resolved` filters turned into SQL in one place
##   (`matchSql()`, which takes no reference), used to list, count and save.  `latest` and `previous` refer to an activity (the newest of those that meet
##   the other criteria; the one that was selected before).  `--invert` negates all of them taken together.
## * **The point `activities/criteria`**: a package may offer an option that picks activities (a `Criterion`: the option's
##   description, and `resolve()`, which gives an SQL condition on the activity `a` and its file `f`).  `climbs` offers `--climbs`.
##   The offered options appear in `--help` and are parsed like the others; the SQL pieces carry the package that wrote them,
##   so this package may run a condition that reads tables it does not.
## * **A subject** (`subject.nim`): contributes the activities to `subject/subjects`, as the default, with how many the user's
##   selection holds.
## * **Map frames** (`mapframes.nim`): the routes of the selected activities and the heat (how often each place was visited), offered to
##   `map/frames` with the style of each.
## * **A calendar frame** (`calendarframe.nim`): the days of the selected activities and the line that sums them up, offered to
##   `calendar/frames`.
## * **A plot frame** (`plotframes.nim`): the impulse of the selected activities each day (by the first selected model),
##   offered to `plot/frames`.
## * The table (`table.nim`) and its rows (`rows.nim`); the delete (`deleterun.nim`).

import ../../core/[extension, manifest]
import ./[calendarframe, command, criterion, mapframes, plotframes, subject]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[subject.contribution(), calendarframe.contribution(), calendarframe.background()] &
    mapframes.contributions() & plotframes.contributions()

const package* = Package(
  depends: @[
    "args", "bundle", "cache", "calendar", "db", "fit", "fold", "geo", "importer",
    "lookup", "near", "map", "model", "names", "plot", "selection", "subject", "tags",
    "ui", "user",
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
