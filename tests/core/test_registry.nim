## The ordering of packages (core/registry.nim) and the generator of the registry (tools/genregistry.nim).

import std/[algorithm, os, sequtils, strutils, unittest]
import nimchoo/core/[package, registry]
import nimchoo/errors
import nimchoo/registry as generated
import ../../tools/genregistry

func pkg(name: string, depends: varargs[string]): Registered =
  Registered(name: name, package: Package(depends: @depends))

func names(ps: seq[Registered]): seq[string] =
  ps.mapIt(it.name)

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
