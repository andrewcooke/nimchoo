import ../../core/package as corePackage

const package* = Package(
  depends:
    @["bytes", "db", "fit", "geo", "hashing", "names", "profiling", "ui", "warnings"],
  fragments: @[],
)
