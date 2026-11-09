## The ordering of packages (core/registry.nim) and the generator of the registry (tools/genregistry.nim).

import std/[algorithm, os, sequtils, strutils, unittest]
import nimchoo/core/[extension, globals, package, registry]
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
    writeFile(root / "a" / "package.nim", "")
    writeFile(root / "a" / "b" / "package.nim", "")
    defer:
      removeDir root
    expect ValueError:
      discard findPackages(root)

  test "a directory without package.nim only groups":
    let root = getTempDir() / "nch-test-genregistry2"
    removeDir root
    createDir root / "group" / "a"
    writeFile(root / "group" / "a" / "package.nim", "")
    defer:
      removeDir root
    check findPackages(root) ==
      @[Found(name: "a", importPath: "packages/group/a/package")]

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

  test "a point gives its values by priority, then in dependency order":
    let e = collectExtensions(@[with("one", ints), with("two", moreInts, "one")])
    check e.get(pointA) == @[1, 2, 3]
    check e.get(pointB) == @["b"]

  test "a point nobody contributed to is empty":
    check collectExtensions(@[pkg("x")]).get(pointA).len == 0

  test "two points of one name but different types are refused, naming the packages":
    expect PackageError:
      discard collectExtensions(@[with("one", ints), with("two", strings, "one")])

  test "the real registry gives the importer the heart-rate step":
    let steps = generated.extensions.get(importStep)
    check steps.len == 1
    check steps[0].channels == @["heart_rate"]
