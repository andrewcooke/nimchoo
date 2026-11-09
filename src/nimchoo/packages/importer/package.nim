import ../../core/manifest

const package* = Package(
  depends:
    @["bytes", "db", "fit", "geo", "hashing", "names", "profiling", "ui", "warnings"],
  fragments: @[
    fragment("001-schema.sql"), # file, activity, coords, segment, route, seen_file
    fragment("002-seen-file-index.sql"),
  ],
)
