## Mutation fuzzing of the importer's reader: damage real files at random (the mutations of tests/support/fitmutate.nim,
## as for `nch fit`); `readActivities` does the arithmetic on times and positions (sessions, timer segments, stretches),
## and must end in success, a FitError or an ImportError, never in anything else.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (mutations per small file, default 60) sets the length; the large files get a tenth of it.

import std/[os, random, strutils, tables, unittest]
import nimchoo/core/errors
import nimchoo/packages/importer/extract
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ../support/[fitmutate, fuzzfiles]

const small = ["sdk", "other", "python-fitparse"]

suite "importer fuzzing":
  let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  proc fuzz(
      paths: seq[string], rounds: int, seed: int64
  ): tuple[stats: string, report: seq[string]] =
    ## Damage each file `rounds` times; read each result with and without the heart-rate channel.
    var originals: seq[seq[byte]]
    for path in paths:
      originals.add readBytes(path)
    var r = initRand(seed)
    var failures: Table[string, string] # signature -> where the input was saved
    var runs, ok, rejected = 0
    for i, path in paths:
      for round in 0 ..< rounds:
        let data = r.mutate(originals[i], originals)
        inc runs
        for channels in [@[], @["heart_rate"]]:
          var ws: seq[Warning]
          try:
            discard readActivities(p, data, ws, channels)
            inc ok
          except FitError, ImportError:
            inc rejected
          except Exception as e: # the point of the test: anything else is a bug
            let signature = signatureOf(e)
            if signature notin failures:
              failures[signature] = saveFailure("import", path, round, data)
    for sig, saved in failures:
      result.report.add sig & "  (saved: " & saved & ")"
    result.stats =
      $runs & " mutations of " & $paths.len & " files: " & $ok & " read, " & $rejected &
      " refused"

  test "damaged small files end in success or an error of ours":
    let (stats, report) = fuzz(fitFiles(0, 12_000, small), rounds, 20261110)
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for l in report:
      checkpoint l
    check report.len == 0

  test "damaged large files end in success or an error of ours":
    # (a few, with fewer rounds: each mutation walks the whole file, and these have developer fields and many messages)
    let paths = fitFiles(12_001, 160_000, @small & @["personal"])
    check paths.len >= 3
    let (stats, report) = fuzz(paths, max(1, rounds div 10), 20261111)
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for l in report:
      checkpoint l
    check report.len == 0

  test "inputs that once broke the reader are read without a Defect":
    let paths = savedFailures("importer")
    check paths.len >= 1
    for path in paths:
      for channels in [@[], @["heart_rate"]]:
        var ws: seq[Warning]
        try:
          discard readActivities(p, readBytes(path), ws, channels)
        except FitError, ImportError:
          discard
