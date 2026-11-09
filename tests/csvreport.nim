## Compare our CSV with the SDK CSV for every file that has one and print the
## differences grouped by (message, field, kind).  Run with `nimble csvreport`.

import std/[algorithm, sequtils, sets, strutils, tables]
import nimchoo/core/errors
import nimchoo/packages/util/bytes/bytes
import nimchoo/fit/command
import nimchoo/profile/load
import nimchoo/fit/tokens
import ./support/csvcompare

type Group = object
  count: int
  files: HashSet[string]
  example: string

proc main() =
  let p = loadProfile("../choochoo/data/sdk/Profile.xlsx")
  let composites = compositeNames(p)
  var groups: Table[string, Group]
  var clean, total = 0
  for pair in sdkPairs():
    inc total
    var lines: seq[string]
    var warnings: seq[Warning]
    var err = ""
    try:
      renderInto(p, readBytes(pair.fitPath), true, lines, warnings)
    except FitError as e:
      err = e.msg
    var ignore: HashSet[string]
    for k in ignoredFields.getOrDefault(pair.name):
      ignore.incl k
    let diffs = compareCsv(lines.join("\n"), readFile(pair.csvPath), composites, ignore)
    let label = pair.dir & "/" & pair.name
    if diffs.len == 0 and err.len == 0:
      inc clean
    else:
      echo label,
        ": ", diffs.len, " diffs", (if err.len > 0: " (FitError: " & err & ")"
        else: "")
    for d in diffs:
      let key = d.message & " " & d.key & " " & $d.kind
      var g = groups.getOrDefault(key)
      inc g.count
      g.files.incl label
      if g.example.len == 0:
        g.example =
          label & " row " & $d.row & ": ours=" & d.ours[0 ..< min(60, d.ours.len)] &
          " theirs=" & d.theirs[0 ..< min(60, d.theirs.len)]
      groups[key] = g
  echo ""
  echo clean, " of ", total, " files identical"
  var keys = toSeq(groups.keys)
  keys.sort(
    proc(a, b: string): int =
      cmp(groups[b].count, groups[a].count)
  )
  for k in keys:
    let g = groups[k]
    var dirs: CountTable[string]
    for f in g.files:
      dirs.inc f.split('/')[0]
    var ds: seq[string]
    for d, n in dirs:
      ds.add d & ":" & $n
    echo g.count, "x [", ds.join(" "), "] ", k
    echo "     e.g. ", g.example

main()
