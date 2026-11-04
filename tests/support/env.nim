## Imported first by tests/all.nim: the tests use a cache directory of their own, never the author's.
## A test that points NCH_CACHE somewhere else puts it back with `useTestCache()` (never unsets it,
## which would send later tests to the author's cache).
import std/os

proc useTestCache*() =
  putEnv("NCH_CACHE", getTempDir() / "nch-test-cache")

useTestCache()
