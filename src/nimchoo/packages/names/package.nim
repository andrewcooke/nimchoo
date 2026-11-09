import ../../core/package as corePackage

const package* = Package(
  depends: @["cache", "db", "download", "geo", "landmark", "ui", "zip"], fragments: @[]
)
