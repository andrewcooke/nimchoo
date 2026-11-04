import std/[os, unittest]
import nimchoo/empty/cachefiles

let dir = getTempDir() / "nch-test-cachefiles"

suite "cache files":
  test "what is said of them":
    check describe(CacheFiles()) == "no cache files"
    check describe(CacheFiles(count: 1, bytes: 12_345)) == "1 cache file (12 kB)"
    check describe(CacheFiles(count: 12, bytes: 3_400_000)) == "12 cache files (3 MB)"
    check describe(CacheFiles(count: 2, bytes: 90)) == "2 cache files (90 bytes)"

  test "they are counted and deleted; other directories stay; a missing cache is nothing":
    removeDir(dir)
    check cacheFiles(dir).count == 0 and removeCacheFiles(dir) == 0
    createDir(dir / "user")
    createDir(dir / "system")
    writeFile(dir / "user" / "a.geojson", "12345")
    writeFile(dir / "user" / "b.csv", "123")
    writeFile(dir / "system" / "c.txt", "x")
    check cacheFiles(dir) == CacheFiles(count: 2, bytes: 8)
    check removeCacheFiles(dir) == 2
    check cacheFiles(dir).count == 0
    check fileExists(dir / "system" / "c.txt")
    check dirExists(dir / "user")
