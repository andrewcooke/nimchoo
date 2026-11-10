## The ordering of packages (core/registry.nim) and the generator of the registry (tools/genregistry.nim).

import std/[algorithm, os, sequtils, strutils, unittest]
import nimchoo/core/[extension, globals, manifest, registry]
import nimchoo/packages/importer/channel
import nimchoo/core/errors
import nimchoo/registry as generated
import ../../tools/genregistry

func pkg(name: string, depends: varargs[string]): Registered =
  Registered(name: name, package: Package(depends: @depends))

func names(ps: seq[Registered]): seq[string] =
  ps.mapIt(it.name)

func names(cs: seq[CommandDecl]): seq[string] =
  cs.mapIt(it.name)

suite "the order of packages":
  test "each package comes after the packages it depends on":
    let ordered = inDependencyOrder(@[pkg("c", "b"), pkg("b", "a"), pkg("a"), pkg("d")])
    check ordered.names == @["a", "b", "c", "d"]

  test "packages that depend on nothing in common are in the order of their names":
    check inDependencyOrder(@[pkg("zed"), pkg("alpha"), pkg("mid", "zed")]).names ==
      @["alpha", "zed", "mid"]

  test "a dependency may be spelt as Nim spells the same name (case after the first letter, underscores)":
    check inDependencyOrder(@[pkg("user_data", "fOld"), pkg("fold")]).names ==
      @["fold", "user_data"]

  test "a package that depends on one that is not there is refused, naming both":
    expect PackageError:
      discard inDependencyOrder(@[pkg("a", "nowhere")])
    try:
      discard inDependencyOrder(@[pkg("a", "nowhere")])
    except PackageError as e:
      check "'a' depends on 'nowhere'" in e.msg

  test "a cycle is refused, and the message gives it":
    try:
      discard
        inDependencyOrder(@[pkg("a", "b"), pkg("b", "c"), pkg("c", "a"), pkg("d")])
      fail()
    except PackageError as e:
      check "a -> b -> c -> a" in e.msg

  test "a package that depends on itself is a cycle":
    expect PackageError:
      discard inDependencyOrder(@[pkg("a", "a")])

  test "a name used twice is refused, even if the spellings differ":
    expect PackageError:
      discard inDependencyOrder(@[pkg("user_data"), pkg("userData")])

func provides(name: string, commands: varargs[string]): Registered =
  let run = proc(g: Globals, args: seq[string]): int {.nimcall, raises: [].} =
    0
  var p = Package()
  for c in commands:
    p.commands.add CommandDecl(name: c, summary: "does " & c, run: run)
  Registered(name: name, package: p)

suite "the commands of the packages":
  test "all of them, by name":
    check collectCommands(@[provides("a", "zed", "alpha"), provides("b", "mid")]).mapIt(
      it.name
    ) == @["alpha", "mid", "zed"]

  test "a name two packages share is refused, naming both":
    try:
      discard collectCommands(@[provides("a", "x"), provides("b", "x")])
      fail()
    except PackageError as e:
      check "'x'" in e.msg and "'a'" in e.msg and "'b'" in e.msg

  test "the usage list has a line for every command, in order, with its summary":
    let text = commandList(
      collectCommands(@[provides("a", "zed", "alpha"), provides("b", "mid")])
    )
    check text.splitLines[0 ..< ^1].len == 3
    check text.contains("  alpha       does alpha\n")
    check text.find("alpha") < text.find("mid") and text.find("mid") < text.find("zed")

  test "the commands of nimchoo have names and summaries, and fit is there and runs":
    let names = generated.commands.names
    check names.len == names.deduplicate.len
    for c in generated.commands:
      check c.name.len > 0 and c.summary.len > 0 and c.run != nil
    check "fit" in names
    let fit = generated.commands.filterIt(it.name == "fit")[0]
    check fit.run(Globals(), @["--help"]) == 0

suite "the generated registry":
  let source = "src" / "nimchoo"

  test "the registry on disk is the one the generator would write":
    check readFile(source / "registry.nim") ==
      registryText(findPackages(source / "packages"))

  test "the packages in the registry are the packages on disk, in dependency order":
    check generated.packages.names.sorted ==
      findPackages(source / "packages").mapIt(it.name).sorted

  test "a package inside a package is refused":
    let root = getTempDir() / "nch-test-genregistry"
    removeDir root
    createDir root / "a" / "b"
    writeFile(root / "a" / "package.nim", "## A.\n")
    writeFile(root / "a" / "b" / "package.nim", "## B.\n")
    defer:
      removeDir root
    expect ValueError:
      discard findPackages(root)

  test "a directory without package.nim only groups":
    let root = getTempDir() / "nch-test-genregistry2"
    removeDir root
    createDir root / "group" / "a"
    writeFile(
      root / "group" / "a" / "package.nim",
      "## Package a.\n##\n## More.\n\nconst x = 1\n",
    )
    defer:
      removeDir root
    check findPackages(root) ==
      @[
        Found(
          name: "a", importPath: "packages/group/a/package", doc: "Package a.\n\nMore."
        )
      ]

  test "the documentation of a package is the ## comment at the top of its package.nim":
    check docOf("## One.\n##\n## Two.\nimport x\n## not this\n") == "One.\n\nTwo."
    check docOf("\n\n## After blank lines.\n") == "After blank lines."
    check docOf("##no space\n##  two spaces\n") == "no space\n two spaces"
    check docOf("import x\n## not at the top\n") == ""
    check docOf("") == ""
    check summaryOf("First.\n\nRest.") == "First."

  test "a package without documentation is refused, with what to write and an example":
    let root = getTempDir() / "nch-test-genregistry3"
    removeDir root
    createDir root / "fresh"
    writeFile(root / "fresh" / "package.nim", "import x\nconst package* = 1\n")
    defer:
      removeDir root
    try:
      discard findPackages(root)
      check false
    except ValueError as e:
      let m = e.msg
      check "package 'fresh' has no documentation" in m
      check "fresh/package.nim" in m
      check "must start with a `##` comment" in m
      check "one-line summary" in m and "For example" in m and
        "    ## What `fresh` is for" in m
      check "text/fold/package.nim" in m # (a model to look at)

  test "a first line too long to be a summary is refused, and the message says how to fix it":
    let root = getTempDir() / "nch-test-genregistry4"
    removeDir root
    createDir root / "wordy"
    writeFile(root / "wordy" / "package.nim", "## " & repeat("long ", 30) & "\n")
    defer:
      removeDir root
    try:
      discard findPackages(root)
      check false
    except ValueError as e:
      check "package 'wordy'" in e.msg and "at most 100" in e.msg
      check "blank `##` line" in e.msg

  test "the registry text has the front page and carries each package's documentation":
    let text = registryText(
      @[
        Found(
          name: "bee",
          importPath: "packages/bee/package",
          doc: "Bees.\n\nMore about bees.",
        ),
        Found(name: "ant", importPath: "packages/util/ant/package", doc: "Ants."),
      ]
    )
    check "## * `ant <packages/util/ant/package.html>`_ - Ants." in text
    check text.find("`ant ") < text.find("`bee ") # (the front page is by name)
    check "summary: \"Bees.\"" in text and "More about bees." in text

  test "every package of the real registry has a summary and documentation":
    for p in generated.packages:
      check p.summary.len > 0 and p.summary.len <= 100
      check p.doc.startsWith(p.summary)

suite "extension points":
  const pointA = ExtensionPoint[int](name: "test/a")
  const pointB = ExtensionPoint[string](name: "test/b")
  const pointAString = ExtensionPoint[string](name: "test/a")

  proc ints(): seq[Contribution] {.nimcall, raises: [].} =
    @[contribute(pointA, 3, priority = 1), contribute(pointA, 1)]

  proc moreInts(): seq[Contribution] {.nimcall, raises: [].} =
    @[contribute(pointA, 2), contribute(pointB, "b")]

  proc strings(): seq[Contribution] {.nimcall, raises: [].} =
    @[contribute(pointAString, "oops")]

  func with(name: string, c: ContributeProc, depends: varargs[string]): Registered =
    Registered(name: name, package: Package(depends: @depends, contributes: c))

  func defining(): Registered =
    ## the package that defines the test points
    Registered(
      name: "test",
      package: Package(
        defines: @[
          PointDecl(name: "test/a", summary: "a number"),
          PointDecl(name: "test/b", summary: "a word"),
        ]
      ),
    )

  test "a point gives its values by priority, then in dependency order":
    let e =
      collectExtensions(@[defining(), with("one", ints), with("two", moreInts, "one")])
    check e.get(pointA) == @[1, 2, 3]
    check e.get(pointB) == @["b"]

  test "a point nobody contributed to is empty":
    check collectExtensions(@[defining(), pkg("x")]).get(pointA).len == 0

  test "two points of one name but different types are refused, naming the packages":
    expect PackageError:
      discard
        collectExtensions(@[defining(), with("one", ints), with("two", strings, "one")])

  test "each contribution says which package made it":
    let e =
      collectExtensions(@[defining(), with("one", ints), with("two", moreInts, "one")])
    check e.contributions("test/a").mapIt(it.source) == @["one", "two", "one"]
    check e.contributions("test/b").mapIt(it.source) == @["two"]
    check e.points == @["test/a", "test/b"]

  test "a contribution to a point nobody defines is refused, naming the package and the point":
    try:
      discard collectExtensions(@[with("one", ints)])
      check false
    except PackageError as e:
      check "'one'" in e.msg and "test/a" in e.msg and "no package defines" in e.msg

  test "the points a package defines are listed with it; the name must start with the package's":
    let ok = Registered(
      name: "x", package: Package(defines: @[PointDecl(name: "x/after", summary: "s")])
    )
    check collectPoints(@[ok]).mapIt(it.owner & ":" & it.point.name) == @["x:x/after"]
    expect PackageError:
      discard collectPoints(
        @[
          Registered(
            name: "x",
            package: Package(defines: @[PointDecl(name: "y/after", summary: "s")]),
          )
        ]
      )
    expect PackageError:
      discard collectPoints(
        @[
          ok,
          Registered(
            name: "x2",
            package: Package(defines: @[PointDecl(name: "x/after", summary: "s")]),
          ),
        ]
      )

  test "the real registry defines five points, and every contribution is to one of them":
    check generated.points.mapIt(it.point.name).sorted ==
      @[
        "activities/criteria", "importer/after", "importer/steps", "user/has",
        "web/pages",
      ]
    for name in generated.extensions.points:
      check name in generated.points.mapIt(it.point.name)
      for c in generated.extensions.contributions(name):
        check c.source.len > 0
    check generated.extensions.contributions("importer/after")[0].source == "selection"

  test "the real registry gives the importer the heart-rate step":
    let steps = generated.extensions.get(importStep)
    check steps.len == 1
    check steps[0].channels == @["heart_rate"]

suite "fragments":
  func withFragments(
      name: string, fragments: seq[Fragment], depends: varargs[string]
  ): Registered =
    Registered(name: name, package: Package(depends: @depends, fragments: fragments))

  test "the fragments come in the order of the packages, each package's in its own order":
    let fs = collectFragments(
      @[
        withFragments(
          "a",
          @[
            Fragment(name: "a/001-x.sql", sql: "create table ta (x)"),
            Fragment(name: "a/002-y.sql", sql: "create table tb (x)"),
          ],
        ),
        withFragments("b", @[Fragment(name: "b/001-z.sql", sql: "create table tc (x)")]),
      ]
    )
    check fs.mapIt(it.name) == @["a/001-x.sql", "a/002-y.sql", "b/001-z.sql"]

  test "a fragment in the wrong package is refused":
    expect PackageError:
      discard collectFragments(
        @[
          withFragments(
            "a", @[Fragment(name: "b/001-x.sql", sql: "create table ta (x)")]
          )
        ]
      )

  test "a table that refers to a table of a package it does not depend on is refused":
    let a = withFragments(
      "a",
      @[Fragment(name: "a/001-x.sql", sql: "create table ta (id integer primary key)")],
    )
    let b = Fragment(
      name: "b/001-x.sql", sql: "create table tb (a integer references ta(id))"
    )
    check collectFragments(@[a, withFragments("b", @[b], "a")]).len == 2
    expect PackageError:
      discard collectFragments(@[a, withFragments("b", @[b])])
