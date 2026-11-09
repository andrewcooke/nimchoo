## Rules about the layout of the source that the compiler does not check.

import std/[os, strutils, unittest]
import ./support/importgraph

suite "structure":
  test "only nch.nim and a package.nim import a command module":
    # (a command is the command-line front of a module: nothing else may
    # depend on it; other code uses the module's library files.  A command package's own package.nim
    # imports its command, to declare it.)
    var offenders: seq[string]
    for path in walkDirRec("src"):
      if not path.endsWith(".nim") or path == "src" / "nch.nim" or
          path.extractFilename == "package.nim":
        continue
      for name in importedNames(readFile(path)):
        if name.lastPathPart == "command":
          offenders.add path & ": " & name
    check offenders == newSeq[string]()
