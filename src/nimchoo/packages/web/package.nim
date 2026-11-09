import ../../core/manifest

const package* = Package(
  depends:
    @["args", "bundle", "cache", "childasync", "db", "selection", "templating", "ui"],
  fragments: @[],
)
