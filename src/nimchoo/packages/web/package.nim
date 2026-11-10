import ../../core/manifest
import ./request

const package* = Package(
  depends: @["args", "bundle", "cache", "childasync", "db", "templating", "ui"],
  fragments: @[],
  defines: @[
    PointDecl(
      name: webPage.name,
      summary:
        "the commands the server may run for a page, and the options they may be given (`map`, `ff`)",
    )
  ],
)
