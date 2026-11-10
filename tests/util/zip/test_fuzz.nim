## Fuzzing of the zip reader (`listEntries`, `extractEntry`, `readEntry`), which reads files from outside (the
## GeoNames downloads, the profile): damaged zip files, stored and deflated, must end in success or a `ZipError`, never
## in a Defect or in a long wait.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 40 files per round.

import std/[monotimes, os, random, strutils, tables, times, unittest]
import nimchoo/core/errors
import nimchoo/packages/util/zip/zipbytes
import ../../support/[fuzzcheck, fuzzfiles, fuzzsamples, zipmutate]

suite "zip fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "damaged zip files end in success or a ZipError, and quickly":
    let originals = zipBases()
    var r = initRand(20261113)
    var failures: Table[string, string] # what was wrong -> where the input was saved
    var runs, ok = 0
    for round in 0 ..< rounds * 40:
      let z = r.damageZip(r.sample(originals))
      inc runs
      var what = ""
      let started = getMonoTime()
      try:
        useZip(z)
        inc ok
      except ZipError:
        discard
      except Exception as e: # the point of the test: nothing else may be raised
        what = signatureOf(e)
      if what == "" and (getMonoTime() - started).inMilliseconds > 2000:
        what = "took more than 2 s"
      if what != "" and what notin failures:
        failures[what] = saveFailure("zip", "zip", round, bytesOf(z), ".zip")
    let stats = $runs & " zip files, " & $ok & " read"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint what & "  (saved: " & saved & ")"
    check failures.len == 0

  test "files that once broke the reader end in success or a ZipError":
    for path in savedFailures("zip", ".zip"):
      try:
        useZip(readFile(path))
      except ZipError:
        discard
