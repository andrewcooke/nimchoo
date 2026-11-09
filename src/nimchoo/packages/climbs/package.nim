import ../../core/package as corePackage

const package* = Package(
  depends: @[
    "db", "fit", "fold", "geo", "importer", "lookup", "names", "profiling", "selection",
    "ui",
  ],
  fragments: @[],
)
