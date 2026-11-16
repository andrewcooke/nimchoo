## `fmt"..."` is a raw string: `\n` in it is a backslash and an n, not a newline.  A test over the whole source for the class of bug.

import std/[os, strutils, unittest]

suite "printing with fmt":
  test "no fmt string holds a backslash escape (it would be printed as it is written)":
    var bad: seq[string]
    for root in ["src", "tests", "tools"]:
      for path in walkDirRec(root):
        if path.endsWith(".nim") and not path.endsWith("registry.nim"):
          var k = 0
          for line in readFile(path).splitLines:
            inc k
            var rest = line
            while true:
              let at = rest.find("fmt\"")
              if at < 0:
                break
              rest = rest[at + 4 ..^ 1]
              let close = rest.find('"')
              if close >= 0 and '\\' in rest[0 ..< close]:
                bad.add path & ":" & $k
    check bad.len == 0
    if bad.len > 0:
      echo bad.join("\n")
