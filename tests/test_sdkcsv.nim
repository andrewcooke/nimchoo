## Our CSV output against the CSVs written by the SDK, for every .fit file
## that has one.  sdk/ and personal/ must match exactly; python-fitparse/ and
## other/ were written by older SDK versions and may differ only in the ways
## listed in `allowed` (csvcompare.nim).

import std/[sets, strutils, tables, unittest]
import nimchoo/binary
import nimchoo/commands/fit
import nimchoo/profile
import nimchoo/tokens
import ./csvcompare

let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
let composites = compositeNames(p)
var used: array[allowed.len, int]

func describe(d: Diff): string =
  "row " & $d.row & " " & $d.kind & " " & d.message & "." & d.key &
    ": ours=" & d.ours & " theirs=" & d.theirs

suite "SDK CSV comparison":
  for pair in sdkPairs():
    test pair.dir & "/" & pair.name:
      var lines: seq[string]
      var warnings: seq[Warning]
      renderInto(p, readBytes(pair.fitPath), true, lines, warnings)
      var ignore, round2: HashSet[string]
      for k in ignoredFields.getOrDefault(pair.name): ignore.incl k
      for k in roundedFields.getOrDefault(pair.name): round2.incl k
      var unexpected: seq[Diff]
      for d in compareCsv(lines.join("\n"), readFile(pair.csvPath), composites,
                          ignore, round2):
        let i = isAllowed(pair.dir, d)
        if i < 0: unexpected.add d
        else: inc used[i]
      for d in unexpected[0 ..< min(5, unexpected.len)]:
        checkpoint describe(d)
      check unexpected.len == 0

  test "every allowed difference is still needed":
    for i, a in allowed:
      checkpoint a.message & "." & a.key & " (" & a.reason & ")"
      check used[i] > 0

  test "sdk and personal files have no allowances":
    for a in allowed:
      check "sdk" notin a.dirs
      check "personal" notin a.dirs
