## Fitness and fatigue: the models, their impulses, the models selection and its curves.
##
## * **A model** (`calc.Model`) is a named set of the variables of the training impulse (gamma, zero, one, the longest gap
##   bridged, the zones, the ceiling above which a reading is a fault of the sensor), of the fitness and fatigue curves (their decay times and their scales in form), and of which
##   activities count (tag patterns: an activity counts if it has a tag matching each; none, all of them).  Models belong
##   to no user.  The program makes one, `default` (the original's), built in: selected for every user from
##   the start, and otherwise like the others (edited, deleted; a rebuild makes it again).
## * **`nch ff`** manages them as an editable type (`editable`; the declaration is `params.modelKind`): `--add NAME`
##   copies `default` or `--base NAME` and then the values given, `--edit NAME` changes values or the name, `--delete`
##   deletes what is listed.  A model's name is written and matched as a tag is (`tags`), but is not one.
## * **The models selection** (`model_selection`) is a subject's, called `ff` in the views (`subject.nim`; the steps of
##   `subject/steps`, `--names` its criteria): `nch plot ff` draws the fitness, fatigue and form of each selected model
##   (`plotframes.nim`; the curves are `curve.nim`, their latest values `stats.nim`), and `nch calendar --shade fitness`
##   (or fatigue, form) shades the days by the first selected model's (`calendarshades.nim`).  The built-in models are selected for every user from the start (a
##   trigger on `user`, and the seed).
## * **The impulses**: an activity's is worked out from its heart rate with a model and the user's FTHR, one lump for each
##   stretch of riding (the importer's `readStretches`), at its centre (`calc` is the arithmetic, pure; `impulses` stores them in
##   `impulse`).  They are worked out when a view needs them, and deleted when the FTHR they were worked out with changes (a
##   trigger of the table) or an edit changes what the model makes of the heart rate, so they are worked out again.  The
##   patterns choose which impulses count (`impulses.userLumps`), so changing them changes no impulse.
##
## The tables (`ff_model`, `ff_model_pattern`, `model_selection`, `impulse`) are this package's.

import ../../core/[extension, manifest]
import ./[calendarshades, command, models, plotframes, subject]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[subject.contribution()] & plotframes.contributions() & calendarshades.contributions()

const package* = Package(
  depends: @[
    "args", "calendar", "channels", "db", "editable", "fit", "fold", "hashing",
    "importer", "plot", "subject", "tags", "ui", "user",
  ],
  fragments: @[
    fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion)
      # ff_model (with `default`), ff_model_pattern, model_selection, impulse
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the models of fitness and fatigue: list, add, edit, delete, choose",
      run: command.run,
      options: command.options,
    )
  ],
  contributes: contributions,
)
