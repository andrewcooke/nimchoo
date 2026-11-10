## Fuzzing of the zip reader (`listEntries`, `extractEntry`, `readEntry`), which reads files from outside (the
## GeoNames downloads, the profile): damaged zip files, stored and deflated, must end in success or a `ZipError`, never
## in a Defect or in a long wait.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 40 files per round.

import std/[monotimes, os, random, strutils, tables, times, unittest]
import nimchoo/core/errors
import nimchoo/packages/util/zip/zipbytes
import ../../support/[fuzzfiles, xlsxbuilder, zipmutate, zips]

proc bases(): seq[string] =
  ## Valid zip files to damage: deflated, stored, several entries, an empty one, a long name.
  let text = repeat("the quick brown fox, 12345; ", 200)
  let entries =
    @[("a.txt", "hello"), ("dir/b.csv", text), ("empty", ""), ("c.txt", text[0 .. 99])]
  @[
    makeZip(entries, deflate = true),
    makeZip(entries, deflate = false),
    makeZip(@[(repeat("n", 300), "x")]),
    makeZip(newSeq[(string, string)]()),
    storedZip(entries),
  ]

proc useZip(z: string) {.raises: [ZipError].} =
  ## Everything the program does with a zip file, with the limits it would use (smaller: the test is quick).
  let entries = listEntries(z)
  for name, e in entries:
    discard extractEntry(z, e, 1_000_000)
  discard readEntry(z, "a.txt", 1_000_000)

suite "zip fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "damaged zip files end in success or a ZipError, and quickly":
    let originals = bases()
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
