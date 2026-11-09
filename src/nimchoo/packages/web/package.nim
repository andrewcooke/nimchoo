import ../../core/package as corePackage

const package* = Package(
  depends:
    @["args", "bundle", "cache", "childasync", "db", "selection", "templating", "ui"],
  fragments: @[],
)
