import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "bundle", "bytes", "lookup", "warnings", "xlsx"],
  fragments: @[],
  commands: @[
    CommandDecl(name: "fit", summary: "read a FIT file and print it", run: command.run)
  ],
)
