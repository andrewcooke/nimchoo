import ../../core/manifest
import ./command
import ./models

const package* = Package(
  depends: @["args", "db", "fit", "hashing", "heartrate", "importer", "user"],
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
