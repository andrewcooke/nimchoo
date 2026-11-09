import std/[os, unittest]
import nimchoo/core/globals
import nimchoo/packages/commands/cachecmd/command as cacheCommand
import ../../support/userdata

let dir = getTempDir() / "nch-test-cache"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)
  putEnv("NCH_CACHE", result / "cache")
  createDir(result / "cache" / "user")
  createDir(result / "cache" / "system")
  createDir(result / "cache" / "data" / "geonames")
  writeFile(result / "cache" / "user" / "heatmap--check-ab.geojson", "{}")
  writeFile(result / "cache" / "user" / "ff--check-cd.csv", "time\n")
  writeFile(result / "cache" / "system" / "libraries.txt", "x")
  writeFile(result / "cache" / "data" / "geonames" / "CL.zip", "zip")
  writeFile(result / "cache" / "server-token", "secret")

proc run(args: varargs[string]): int =
  cacheCommand.run(globals("unused.db"), @args)

suite "nch cache":
  teardown:
    delEnv("NCH_CACHE")
  test "no arguments says what there is and changes nothing":
    let d = fresh("show")
    check run() == exitOk
    check fileExists(d / "cache" / "user" / "ff--check-cd.csv") and
      fileExists(d / "cache" / "data" / "geonames" / "CL.zip")
  test "--delete KIND deletes that kind only, with no -f":
    let d = fresh("one")
    check run("--delete", "csv") == exitOk
    check not fileExists(d / "cache" / "user" / "ff--check-cd.csv")
    check fileExists(d / "cache" / "user" / "heatmap--check-ab.geojson") and
      fileExists(d / "cache" / "system" / "libraries.txt")
    check run("--delete", "csv") == exitOk # nothing left: fine
  test "several kinds, and all":
    let d = fresh("several")
    check run("--delete", "geojson", "downloads") == exitOk
    check not fileExists(d / "cache" / "user" / "heatmap--check-ab.geojson") and
      not dirExists(d / "cache" / "data")
    check fileExists(d / "cache" / "system" / "libraries.txt")
    check run("--delete", "all") == exitOk
    check not dirExists(d / "cache" / "system") and
      not fileExists(d / "cache" / "user" / "ff--check-cd.csv")
    check fileExists(d / "cache" / "server-token")
  test "the database is neither touched nor made":
    let d = fresh("nodb")
    check run("--delete", "all") == exitOk
    check not fileExists("unused.db")
  test "bad arguments":
    discard fresh("bad")
    check run("--delete") == exitUsage
    check run("--delete", "data") == exitUsage
    check run("--nonesuch") == exitUsage
    check run("csv") == exitUsage
    check run("--help") == exitOk
