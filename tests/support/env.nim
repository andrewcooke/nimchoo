## Imported first by tests/all.nim: the tests use a cache directory of their own, never the author's.
import std/os
putEnv("NCH_CACHE", getTempDir() / "nch-test-cache")
