## Mutation fuzzing of the FIT decoder: damage real files at random; reading
## (and printing, which is where a corrupt date once reached a Defect) must end
## in success or a FitError, never in anything else.  The seed is fixed, so a
## failure repeats; the failing input is saved (the path is in the message).
##
## NCH_FUZZ_ROUNDS (mutations per file, default 60) lets a longer run be made by
## hand.

import std/[os, random, strutils, tables, unittest]
import nimchoo/core/errors
import nimchoo/packages/commands/fitcmd/command
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ../support/[fitmutate, fuzzfiles]

suite "FIT fuzzing":
  let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "the walker follows the records of most sample files to the end":
    # (if it did not, the structural damage would silently be blind damage)
    var whole = 0
    let paths = fitFiles(0, 12_000, ["sdk", "other", "python-fitparse"])
    for path in paths:
      if walk(readBytes(path)).complete:
        inc whole
    check whole * 10 >= paths.len * 8

  test "damaged files end in success or a FitError":
    let paths = fitFiles(0, 12_000, ["sdk", "other", "python-fitparse"])
    var originals: seq[seq[byte]]
    for path in paths:
      originals.add readBytes(path)
    var r = initRand(20261108)
    var failures: Table[string, string] # signature -> where the input was saved
    var runs, ok, rejected, noisy = 0
    for i, path in paths:
      for round in 0 ..< rounds:
        let data = r.mutate(originals[i], originals)
        inc runs
        for csv in [false, true]:
          var lines: seq[string]
          var warnings: seq[Warning]
          try:
            renderInto(p, data, csv, lines, warnings)
            if csv:
              inc ok
              if warnings.len > 0:
                inc noisy
          except FitError:
            if csv:
              inc rejected
          except Exception as e: # the point of the test: anything else is a bug
            let signature = signatureOf(e)
            if signature notin failures:
              failures[signature] = saveFailure("fit", path, round, data)
    var report: seq[string]
    for sig, saved in failures:
      report.add sig & "  (saved: " & saved & ")"
    let stats =
      $runs & " mutations of " & $paths.len & " files: " & $ok & " read (" & $noisy &
      " with warnings), " & $rejected & " refused"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for l in report:
      checkpoint l
    check report.len == 0

  test "files that once broke the reader end in success or a FitError":
    for path in savedFailures("fit", ".fit"):
      var lines: seq[string]
      var warnings: seq[Warning]
      for csv in [false, true]:
        try:
          renderInto(p, readBytes(path), csv, lines, warnings)
        except FitError:
          discard
