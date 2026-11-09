import std/[os, unittest]
import nimchoo/packages/cache/files

let dir = getTempDir() / "nch-test-cachefiles"

proc put(path, text: string) =
  createDir(parentDir(path))
  writeFile(path, text)

suite "cache files: kinds":
  test "names, case folded":
    var k: Kind
    check parseKind("GeoJSON", k) and k == ckGeojson
    check parseKind("downloads", k) and k == ckDownloads
    check not parseKind("data", k)
    check kindNames() == "downloads, system, geojson, csv, html"
  test "what is said of a use":
    check describe(Use()) == "no files"
    check describe(Use(count: 1, bytes: 12_345)) == "1 file (12kB)"
    check describe(Use(count: 12, bytes: 3_400_000)) == "12 files (3.4MB)"
    check describe(Use(count: 2, bytes: 90)) == "2 files (90B)"

suite "cache files: counting and deleting":
  setup:
    removeDir(dir)
    put(dir / "user" / "a.geojson", "12345")
    put(dir / "user" / "b.csv", "123")
    put(dir / "user" / "c.html", "<p>")
    put(dir / "system" / "d.txt", "x")
    put(dir / "data" / "geonames" / "CL.zip", "zip")
    put(dir / "server-token", "secret")
  test "each kind is counted on its own":
    check useOf(dir, ckGeojson) == Use(count: 1, bytes: 5)
    check useOf(dir, ckCsv) == Use(count: 1, bytes: 3)
    check useOf(dir, ckHtml) == Use(count: 1, bytes: 3)
    check useOf(dir, ckSystem) == Use(count: 1, bytes: 1)
    check useOf(dir, ckDownloads) == Use(count: 1, bytes: 3)
  test "deleting a kind leaves the others, and the token":
    check deleteKind(dir, ckCsv) == Use(count: 1, bytes: 3)
    check not fileExists(dir / "user" / "b.csv")
    check fileExists(dir / "user" / "a.geojson") and fileExists(dir / "user" / "c.html")
    check deleteKind(dir, ckDownloads).count == 1
    check not dirExists(dir / "data")
    check deleteKind(dir, ckSystem).count == 1
    check not dirExists(dir / "system")
    check fileExists(dir / "server-token") and dirExists(dir / "user")
    check deleteKind(dir, ckCsv).count == 0 # nothing left: fine
  test "a missing cache is nothing":
    removeDir(dir)
    for k in Kind:
      check useOf(dir, k).count == 0 and deleteKind(dir, k).count == 0
