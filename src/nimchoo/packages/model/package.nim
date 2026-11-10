## The training impulse: models, and the impulses worked out with them.
##
## A model is a named set of variables (`nch models`); models belong to no user, and the program carries a default.  The
## impulse of an activity is worked out from its heart rate, hour by hour, with a model and the user's FTHR (`calc` is the
## arithmetic, pure; `impulses` stores them in `impulse`, with `ff_model`, the tables this package owns).  They are worked out
## when `ff` needs them, and deleted when the FTHR they were worked out with changes (a trigger of the table), so they are
## worked out again.

import ../../core/manifest
import ./command
import ./models

const package* = Package(
  depends: @["args", "db", "fit", "hashing", "heartrate", "importer", "ui", "user"],
  fragments: @[
    fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion),
    fragment("002-impulse-index.sql"), # ff_model (with `default`), impulse
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the models: sets of variables for the training impulse",
      run: command.run,
    )
  ],
)
