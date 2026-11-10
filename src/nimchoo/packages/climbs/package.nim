## Climbs: found in the rides, named, and ranked.
##
## The climbs are found in the rides once (the first time `nch climbs` runs it works out those of every activity not yet looked
## at, about a minute for two thousand rides) and kept in `sector`, `effort` and `climbs_done`, the tables this package owns.
## A ride that goes over part of a climb but not all of it makes a climb of its own.  Climbs are shared by all users; a climb
## is never deleted one at a time (`--edit NAME --retire` hides one), only all together (`climbs --all --delete -f`).
##
## **Describing a climb** (decided 2026-11-05): `Cerro San Luis₄  4 0.5km +89m 17.8%` (name, category, length, gain,
## gradient).  A name shared by several climbs carries a **kept number as a subscript** (`sector.name_n`, given when the climb
## gets its name, never renumbered), typed as `Cerro San Luis₄`, `Cerro San Luis 4` or `Cerro San Luis4`.  In `nch climbs`
## the summary follows: attempts, best, latest and its personal rank (`3 of 12`: among the user's own attempts); `--everyone`
## swaps it for the leaderboard (riders, fastest and who, your best's place among each person's best); the two ranks are never
## shown together, are worked out when asked for and never stored.  `-v` lists the attempts.  The selection chooses the climbs,
## never the attempts.
##
## Offers `--climb TEXT...` to `nch activities` (the point `activities/criteria`): the activities that have an effort on a
## climb whose name holds the text.

import ../../core/[extension, manifest]
import ../activities/criterion
import ./[command, criterion]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(activityCriterion, climbCriterion)]

const package* = Package(
  depends: @[
    "activities", "args", "confirm", "db", "fit", "fold", "geo", "importer", "lookup",
    "names", "profiling", "selection", "ui", "user",
  ],
  fragments: @[
    fragment("001-schema.sql"), # sector (with retired), effort, climbs_done
    fragment("002-name-number.sql"), # sector.name_n
    fragment("003-effort-index.sql"), # effort(activity_id)
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the climbs of the selected activities, with times and ranks",
      run: command.run,
      options: command.options,
    )
  ],
  contributes: contributions,
)
