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
  exec "nim c -d:release --checks:on --hints:off -o:nch src/nch.nim"      # (some tests run ./nch)
  exec "nim c -r -d:release --checks:on -d:nchSmallPlaces --hints:off tests/all.nim"   # (a short list of places: fast databases)

task testdebug, "Run all tests as a debug build (slower; for tracking down a failure)":
  exec "nim c --hints:off -o:nch src/nch.nim"
  exec "nim c -r -d:nchSmallPlaces --hints:off tests/all.nim"

task csvreport, "Compare our CSV output with the SDK CSVs (differences by group)":
  exec "nim c -r -d:release --hints:off --warnings:off -o:tests/csvreport tests/csvreport.nim"
