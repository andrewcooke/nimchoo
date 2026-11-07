# Package

version = "0.1.0"
author = "andrew cooke"
description = "lightweight tools for fitness data (rework of choochoo)"
license = "MIT"
srcDir = "src"
bin = @["nch"]

# Dependencies

requires "nim >= 2.2.0"
requires "zippy >= 0.10.4"
requires "db_connector"
requires "checksums"

task test,
  "Run all tests (optimised, with run-time checks on: about 5x faster than a debug build)":
  # (some tests run a program: built like the tests, and kept apart from ./nch so that a test build never
  # replaces the one you use)
  exec "nim c -d:release -d:ssl --checks:on --hints:off -o:nch-test src/nch.nim"
  exec "nim c -r -d:release -d:ssl --checks:on --hints:off tests/all.nim"

task prod,
  "Build ./nch for use: optimised (-d:release); this is the build the author runs":
  # The git commit is handed to the compiler as a define, so that only src/nimchoo/version.nim changes between
  # builds and the rest comes from Nim's cache (no --forceBuild: about 4 to 6 s for a typical edit, not 18).
  let (hash, hashCode) = gorgeEx("git rev-parse --short HEAD")
  let (changes, changesCode) = gorgeEx("git status --porcelain --untracked-files=no")
  let commit =
    if hashCode == 0:
      " -d:nchCommit=" & hash.strip
    else:
      ""
  let dirty = if changesCode == 0 and changes.strip.len > 0: " -d:nchDirty" else: ""
  exec "nim c -d:release -d:ssl" & commit & dirty & " --hints:off -o:nch src/nch.nim"

task testdebug, "Run all tests as a debug build (slower; for tracking down a failure)":
  exec "nim c -d:ssl --hints:off -o:nch-test src/nch.nim"
  exec "nim c -r -d:ssl --hints:off tests/all.nim"

task csvreport, "Compare our CSV output with the SDK CSVs (differences by group)":
  exec "nim c -r -d:release --hints:off -o:tests/csvreport tests/csvreport.nim"
