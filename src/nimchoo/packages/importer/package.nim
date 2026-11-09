import ../../core/manifest

const package* = Package(
  depends:
    @["bytes", "db", "fit", "geo", "hashing", "names", "profiling", "ui", "warnings"],
  fragments: @[],
)
