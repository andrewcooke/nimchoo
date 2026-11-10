import ../../core/manifest

const package* = Package(
  depends: @["args", "bundle", "cache", "childasync", "db", "templating", "ui"],
  fragments: @[],
)
