## The training impulse: models, the impulses worked out with them, and the models selection.
##
## * **A model** (`calc.Model`) is a named set of the variables of the training impulse (gamma, zero, one, the longest gap
##   bridged, the zones), of the fitness and fatigue curves (their decay times and their scales in form), and of which
##   activities count (tag patterns: an activity counts if it has a tag matching each; none, all of them).  Models belong
##   to no user.  The program carries one, `default` (the original's), built in: it is never changed or deleted.
## * **`nch models`** manages them as an editable type (`editable`; the declaration is `params.modelKind`): `--add NAME`
##   copies `default` or `--base NAME` and then the values given, `--edit NAME` changes values or the name, `--delete`
##   deletes what is listed.  A model's name is written and matched as a tag is (`tags`), but is not one.
## * **The models selection** (`model_selection`) is a subject's (`subject/steps`: `--names` are its criteria): it is what
##   the views of fitness and fatigue will show.  The built-in models are selected for every user from the start (a
##   trigger on `user`, and the seed).
## * **The impulses**: an activity's is worked out from its heart rate with a model and the user's FTHR, one lump for each
##   stretch of riding (the importer's `segment`), at its centre (`calc` is the arithmetic, pure; `impulses` stores them in
##   `impulse`).  They are worked out when `ff` needs them, and deleted when the FTHR they were worked out with changes (a
##   trigger of the table) or an edit changes what the model makes of the heart rate, so they are worked out again.  The
##   patterns choose which impulses count (`impulses.userLumps`), so changing them changes no impulse.
##
## The tables (`ff_model`, `ff_model_pattern`, `model_selection`, `impulse`) are this package's.

import ../../core/manifest
import ./command
import ./models

const package* = Package(
  depends: @[
    "args", "db", "editable", "fit", "fold", "hashing", "heartrate", "importer",
    "subject", "tags", "ui", "user",
  ],
  fragments: @[
    fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion)
      # ff_model (with `default`), ff_model_pattern, model_selection, impulse
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the models: sets of variables for the training impulse",
      run: command.run,
      options: command.options,
    )
  ],
)
