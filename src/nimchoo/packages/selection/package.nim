import ../../core/manifest

const package* = Package(
  depends: @["db", "hashing", "importer"],
  fragments: @[
    fragment("001-schema.sql"), # selection
    fragment("002-activity-index.sql"),
  ],
)
