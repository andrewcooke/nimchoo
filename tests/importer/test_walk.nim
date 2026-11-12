import std/[os, sequtils, strutils, unittest]
import nimchoo/packages/importer/walk

let top = getTempDir() / "nch-test-walk"

proc fresh(name: string): string =
  result = top / name
  removeDir(result)
  createDir(result)

proc touch(path: string) =
  createDir(parentDir(path))
  writeFile(path, "x")

proc relative(root: string, paths: seq[string]): seq[string] =
  paths.mapIt(it.relativePath(root))

suite "import: finding the FIT files":
  test "FIT files in directories, in sorted order; other files are not":
    let d = fresh("plain")
    touch(d / "b.fit")
    touch(d / "a" / "z.FIT")
    touch(d / "a" / "notes.txt")
    check relative(d, fitFiles(d)) == @["a/z.FIT", "b.fit"]

  test "a link to a file, and a link to a directory, are followed":
    let d = fresh("links")
    touch(d / "real" / "one.fit")
    touch(d / "real" / "sub" / "two.fit")
    createDir(d / "links")
    createSymlink(d / "real" / "one.fit", d / "links" / "uno.fit")
    createSymlink(d / "real" / "sub", d / "links" / "dir")
    let found = relative(d / "links", fitFiles(d / "links"))
    check found == @["dir/two.fit", "uno.fit"]

  test "a link to a parent is a loop, and ends":
    let d = fresh("loop")
    touch(d / "a" / "x.fit")
    createSymlink(d, d / "a" / "up")
    check relative(d, fitFiles(d)) == @["a/x.fit"]

  test "a file reached by two routes is one file":
    let d = fresh("twice")
    touch(d / "real" / "x.fit")
    createSymlink(d / "real", d / "alias")
    createSymlink(d / "real" / "x.fit", d / "also.fit")
    check fitFiles(d).len == 1

  test "a link to a missing file is returned, so that the import can say it cannot be read":
    let d = fresh("broken")
    createSymlink(d / "nothing.fit", d / "gone.fit")
    check relative(d, fitFiles(d)) == @["gone.fit"]
    check fitFiles(d)[0].fileExists == false

  test "a directory that is not there is an error":
    expect OSError:
      discard fitFiles(top / "no such directory")
