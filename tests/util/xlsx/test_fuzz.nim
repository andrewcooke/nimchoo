## Fuzzing of the xlsx reader (`openWorkbook`, `rows`), which reads Profile.xlsx (a file the user can name with
## `--profile`): a workbook that uses all it understands (shared strings, rich text, inline strings, both ways of naming a
## sheet's file) is damaged, in its zip container and in the xml of each part.  The result must be success or an
## `XlsxError`, never a Defect or a long wait.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 40 files per round.

import std/[monotimes, os, random, strutils, tables, times, unittest]
import nimchoo/core/errors
import nimchoo/packages/util/xlsx/xlsx
import ../../support/[fuzzcheck, fuzzfiles, fuzzsamples, xlsxbuilder, xlsxmutate]

suite "xlsx fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "the workbook that is damaged is good to begin with":
    let wb = openWorkbook(storedZip(xlsxParts))
    check wb.rows("One")[0].cell(1) == "alpha"
    check wb.rows("One")[0].cell(27) == "x"
    check wb.rows("One")[2].cell(2) == "hi & bye"
    check wb.rows("Two")[1].cell(0) == "beta"
    check wb.rows("Two")[1].cell(25) == "3.5"

  test "damaged workbooks end in success or an XlsxError, and quickly":
    var r = initRand(20261114)
    var failures: Table[string, string] # what was wrong -> where the input was saved
    var runs, ok = 0
    for round in 0 ..< rounds * 40:
      let x = r.damagedXlsx(xlsxParts)
      inc runs
      var what = ""
      let started = getMonoTime()
      try:
        useXlsx(x)
        inc ok
      except XlsxError:
        discard
      except Exception as e: # the point of the test: nothing else may be raised
        what = signatureOf(e)
      if what == "" and (getMonoTime() - started).inMilliseconds > 2000:
        what = "took more than 2 s"
      if what != "" and what notin failures:
        failures[what] = saveFailure("xlsx", "xlsx", round, bytesOf(x), ".xlsx")
    let stats = $runs & " workbooks, " & $ok & " read"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint what & "  (saved: " & saved & ")"
    check failures.len == 0
    check ok > runs div 10
      # (damage that is always refused would test nothing past the checks)

  test "files that once broke the reader end in success or an XlsxError":
    for path in savedFailures("xlsx", ".xlsx"):
      try:
        useXlsx(readFile(path))
      except XlsxError:
        discard
