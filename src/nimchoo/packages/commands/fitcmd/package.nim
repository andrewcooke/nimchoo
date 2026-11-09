import ../../../core/package as corePackage
import ./command

const package* = Package(
  depends: @["args", "bytes", "fit", "warnings"],
  commands: @[
    CommandDecl(name: "fit", summary: "read a FIT file and print it", run: command.run)
  ],
)
