## Import paths with templates (src/nimchoo/packages/importer/paths.nim).

import std/[options, os, sequtils, strutils, unittest]
import nimchoo/packages/importer/[channel, paths]

let dir = getTempDir() / "nch-test-paths"

proc label(key, value: string): PathLabel =
  PathLabel(key: (if key.len > 0: some(key) else: none(string)), value: value)

proc touch(path: string) =
  createDir(path.parentDir)
  writeFile(path, "")

proc tree(): string =
  ## bike/cotic/a.fit, bike/cotic/2025/b.fit, bike/uk/c.fit, bike/uk/notes.txt, run/d.fit
  removeDir(dir)
  for p in [
    "bike/cotic/a.fit", "bike/cotic/2025/b.fit", "bike/uk/c.fit", "bike/uk/notes.txt",
    "run/d.fit",
  ]:
    touch(dir / p)
  dir

proc found(arg: string): seq[(string, seq[PathLabel])] =
  for m in parseTemplate(arg).t.get.expand:
    result.add (m.path.relativePath(dir), m.labels)

suite "import paths: templates":
  test "a path with { or * is a template; others are files and directories as they are":
    check "~/fit/bike/{bike}".isTemplate
    check "fit/*/x.fit".isTemplate
    check not "fit/bike/a.fit".isTemplate

  test "the directory searched from is what comes before the first part with a template; ~ is home":
    check parseTemplate("~/fit/{bike}").t.get.root == getHomeDir() / "fit"
    check parseTemplate("/a/b/{x}/c").t.get.root == "/a/b"
    check parseTemplate("{x}/c").t.get.root == "."

  test "what cannot be read is said":
    check parseTemplate("a/{bike/c").problem.get.contains("not closed")
    check parseTemplate("a/{x}}/c").problem.get.contains("closes nothing")
    check parseTemplate("a/{x}{y}").problem.get.contains("nothing between")
    check parseTemplate("a/{x}*").problem.get.contains("nothing between")
    check parseTemplate("a/{b c}").problem.get.contains("name in {...}")

  test "a template ending at a directory means every .fit file under it, with what the directory caught":
    let d = tree()
    check found(d / "bike/{bike}") ==
      @[
        ("bike/cotic/2025/b.fit", @[label("bike", "cotic")]),
        ("bike/cotic/a.fit", @[label("bike", "cotic")]),
        ("bike/uk/c.fit", @[label("bike", "uk")]),
      ]

  test "{} keeps a value with no name; * matches and keeps nothing; text around them must match":
    let d = tree()
    check found(d / "*/{bike}/{}.fit") ==
      @[
        ("bike/cotic/a.fit", @[label("bike", "cotic"), label("", "a")]),
        ("bike/uk/c.fit", @[label("bike", "uk"), label("", "c")]),
      ]
    check found(d / "bike/{bike}/20*").mapIt(it[0]) == @["bike/cotic/2025/b.fit"]
    check found(d / "{kind}/c*").mapIt(it[0]) ==
      @["bike/cotic/2025/b.fit", "bike/cotic/a.fit"] # (c* is the directory cotic)
    check found(d / "nothing/{x}").len == 0
