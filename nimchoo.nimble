# Package

version       = "0.1.0"
author        = "andrew cooke"
description   = "lightweight tools for fitness data (rework of choochoo)"
license       = "MIT"
srcDir        = "src"
bin           = @["nch"]

# Dependencies

requires "nim >= 2.2.0"
requires "zippy >= 0.10.4"
requires "db_connector"
requires "checksums"

task test, "Run all tests (optimised, with run-time checks on: about 5x faster than a debug build)":
  # (some tests run a program: built like the tests, with the short list of places, and kept apart
  # from ./nch so that a test build never replaces the one you use)
  exec "nim c -d:release --checks:on -d:nchSmallPlaces --hints:off -o:nch-test src/nch.nim"
  exec "nim c -r -d:release --checks:on -d:nchSmallPlaces --hints:off tests/all.nim"   # (a short list of places: fast databases)

task prod, "Build ./nch for use: optimised (-d:release); this is the build the author runs":
  exec "nim c -d:release --hints:off -o:nch src/nch.nim"

task testdebug, "Run all tests as a debug build (slower; for tracking down a failure)":
  exec "nim c -d:nchSmallPlaces --hints:off -o:nch-test src/nch.nim"
  exec "nim c -r -d:nchSmallPlaces --hints:off tests/all.nim"

task csvreport, "Compare our CSV output with the SDK CSVs (differences by group)":
  exec "nim c -r -d:release --hints:off --warnings:off -o:tests/csvreport tests/csvreport.nim"
