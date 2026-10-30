## Our CSV output against the CSVs written by the SDK, for the .fit files in
## sdk/ and personal/ (whose CSVs match the SDK version of Profile.xlsx).  They
## must match exactly, apart from the rules in csvcompare.nim.

import std/[sets, strutils, tables, unittest]
import nimchoo/binary
import nimchoo/commands/fit
import nimchoo/profile
import nimchoo/tokens
import ./csvcompare

let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
let composites = compositeNames(p)

func describe(d: Diff): string =
  "row " & $d.row & " " & $d.kind & " " & d.message & "." & d.key &
    ": ours=" & d.ours & " theirs=" & d.theirs

suite "SDK CSV comparison":
  for pair in sdkPairs():
    test pair.dir & "/" & pair.name:
      var lines: seq[string]
      var warnings: seq[Warning]
      renderInto(p, readBytes(pair.fitPath), true, lines, warnings)
      var ignore: HashSet[string]
      for k in ignoredFields.getOrDefault(pair.name): ignore.incl k
      let diffs = compareCsv(lines.join("\n"), readFile(pair.csvPath),
                             composites, ignore)
      for d in diffs[0 ..< min(5, diffs.len)]:
        checkpoint describe(d)
      check diffs.len == 0
