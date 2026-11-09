## The rule about imports (PACKAGES.md, "Layout and rules" 4), on made-up trees and on the real one.

import std/[os, sequtils, strutils, tables, unittest]
import nimchoo/registry as generated
import ../support/importgraph

proc tree(files: openArray[(string, string)]): Table[string, string] =
  for (path, text) in files:
    result[path] = text

proc found(v: seq[Violation]): seq[string] =
  v.mapIt(it.file & " -> " & it.imports)

suite "reading import lines":
  test "the forms of import":
    check importedNames("import std/os\nimport ../a/b, ./c\nimport ../d/[e, f as g]\n") ==
      @["std/os", "../a/b", "./c", "../d/e", "../d/f"]

  test "a list over several lines, with comments":
    check importedNames(
      "import\n  a, # why\n  b/[c,\n    d]\n#[ import x ]#\nlet y = 1\n"
    ) == @["a", "b/c", "b/d"]

  test "from, except and as":
    check importedNames("from ../a import b\nimport ../c except d\nimport ../e as f\n") ==
      @["../a", "../c", "../e"]

  test "an import in the middle of a line or indented is not read":
    check importedNames("let s = \"import x\"\nwhen true:\n  import std/posix\n").len ==
      0

suite "the rule about packages":
  let depends = {"b": @["a"], "a": @[], "c": @[]}.toTable

  test "a package may import itself, core, its dependencies and the libraries":
    let t = tree {
      "core/x.nim": "import std/os",
      "packages/a/package.nim": "",
      "packages/a/one.nim": "import ./two, ../../core/x, std/os, db_connector/db_sqlite",
      "packages/a/two.nim": "",
      "packages/g/b/package.nim": "",
      "packages/g/b/three.nim": "import ../../a/one",
    }
    check violations(t, depends).found == newSeq[string]()

  test "a package may not import one it does not depend on":
    let t = tree {
      "packages/a/package.nim": "",
      "packages/a/one.nim": "import ../c/four",
      "packages/c/package.nim": "",
      "packages/c/four.nim": "",
    }
    let v = violations(t, depends)
    check v.found == @["packages/a/one.nim -> packages/c/four.nim"]
    check "'a' does not declare a dependency on 'c'" in v[0].why

  test "dependencies are one way":
    let t = tree {
      "packages/a/package.nim": "",
      "packages/a/one.nim": "import ../b/three",
      "packages/b/package.nim": "",
      "packages/b/three.nim": "",
    }
    check violations(t, depends).found == @[
      "packages/a/one.nim -> packages/b/three.nim"
    ]

  test "core imports no package":
    let t = tree {
      "core/x.nim": "import ../packages/a/one",
      "packages/a/package.nim": "",
      "packages/a/one.nim": "",
    }
    check violations(t, depends).found == @["core/x.nim -> packages/a/one.nim"]

  test "a file in a subdirectory of a package belongs to the package":
    let t = tree {
      "packages/a/package.nim": "",
      "packages/a/sub/deep.nim": "import ../one",
      "packages/a/one.nim": "",
    }
    check violations(t, depends).found == newSeq[string]()

  test "a package may not import a module that is outside the packages":
    let t = tree {
      "packages/a/package.nim": "",
      "packages/a/one.nim": "import ../../errors",
      "errors.nim": "",
      "old/thing.nim": "import ../packages/c/four",
      "packages/c/package.nim": "",
      "packages/c/four.nim": "",
    }
    check violations(t, depends).found == @["packages/a/one.nim -> errors.nim"]

suite "the packages of nimchoo":
  test "every import in a package or in core follows the rule":
    var t: Table[string, string]
    let root = "src" / "nimchoo"
    for path in walkDirRec(root, relative = true):
      if path.endsWith(".nim"):
        t[path] = readFile(root / path)
    var depends: Table[string, seq[string]]
    for p in generated.packages:
      depends[p.name] = p.package.depends
    let bad = violations(t, depends)
    check bad.mapIt(it.file & " imports " & it.imports & ": " & it.why) ==
      newSeq[string]()
