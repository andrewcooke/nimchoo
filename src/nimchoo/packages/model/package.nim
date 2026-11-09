import ../../core/manifest
import ./models

const package* = Package(
  depends: @["db", "fit", "hashing", "heartrate", "importer", "user"], fragments: @[
    fragment("001-schema.sql").withSeed(seedDefaultModel, seedVersion),
    fragment("002-impulse-index.sql"), # ff_model (with `default`), impulse
  ]
)
