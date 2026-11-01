## Rules about the layout of the source that the compiler does not check.

import std/[os, strutils, unittest]

suite "structure":
  test "only nch.nim imports a command module":
    # (a command is the command-line front of a module: nothing else may
    # depend on it; other code uses the module's library files)
    var offenders: seq[string]
    for path in walkDirRec("src"):
      if not path.endsWith(".nim") or path == "src" / "nch.nim": continue
      for line in readFile(path).splitLines:
        let l = line.strip
        if l.startsWith("import ") and
           (l.contains("/command") or l.contains("[command") or l.contains(", command")):
          offenders.add path & ": " & l
    check offenders == newSeq[string]()

