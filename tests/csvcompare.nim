## Compare our SDK-format CSV with the CSV written by the SDK's FitCSVTool
## (-defn), following the rules of choochoo's CSVEqualContext:
##  * same number of rows; the first three cells (type, local number, message)
##    of each row must match;
##  * then fields are compared by name: value and (if we have a value) units;
##  * the name "unknown" and empty names are ignored;
##  * `.0` is stripped, False/True are 0/1 (and numbers are compared as floats);
##  * the SDK shows composite fields (eg altitude, speed) as well as their
##    components; we only emit the components, so SDK-only composite names
##    are skipped.

import std/[algorithm, options, os, parsecsv, sequtils, sets, streams, strutils, tables]
import nimchoo/profile

type
  DiffKind* = enum
    dkRowCount, dkHeader, dkMissing, dkExtra, dkValue, dkUnits

  Diff* = object
    row*: int            ## 0-based, after the title row
    kind*: DiffKind
    message*: string
    key*: string
    ours*, theirs*: string

  Triples = Table[string, (string, string)]  ## name -> (value, units)

proc readCsv(text: string): seq[seq[string]] =
  var x: CsvParser
  x.open(newStringStream(text), "csv")
  while x.readRow(): result.add x.row
  x.close()

func triples(row: seq[string]): Triples =
  for i in countup(3, row.high, 3):
    let value = if i + 1 < row.len: row[i + 1] else: ""
    let units = if i + 2 < row.len: row[i + 2] else: ""
    result[row[i]] = (value, units)  # as choochoo, the last one wins

func fixValue(v: string): string =
  result = v
  if result.endsWith(".0"): result.setLen(result.len - 2)
  if result == "False": result = "0"
  if result == "True": result = "1"

func sameNumber(a, b: string): bool =
  try: parseFloat(a) == parseFloat(b)
  except ValueError: false

func sameValue(a, b: string): bool =
  ## Equal after choochoo's fixes; arrays element by element, numbers as floats.
  let (x, y) = (fixValue(a), fixValue(b))
  if x == y: return true
  let (xs, ys) = (x.split('|'), y.split('|'))
  if xs.len != ys.len: return false
  for i in 0 ..< xs.len:
    let (u, v) = (fixValue(xs[i]), fixValue(ys[i]))
    if u != v and not sameNumber(u, v): return false
  true

func rounded(v: string): string =
  ## `v` rounded (half up) to 2 decimal places, if it is a number with more.
  try:
    let x = parseFloat(v)
    if '.' in v and v.split('.')[1].len > 2:
      return formatFloat(x + 0.0000001, ffDecimal, 2)
  except ValueError: discard
  v

func compositeNames*(p: Profile): Table[string, HashSet[string]] =
  ## message name -> names of its composite fields
  for m in p.messages.values:
    for f in m.fields.values:
      if f.kind == fkComposite:
        result.mgetOrPut(m.name, initHashSet[string]()).incl f.name

proc compareCsv*(ours, theirs: string,
                 composites: Table[string, HashSet[string]],
                 ignore: HashSet[string] = initHashSet[string](),
                 round2: HashSet[string] = initHashSet[string]()): seq[Diff] =
  ## Differences between our CSV text and the SDK's.  `theirs` starts with a
  ## title row, which is dropped.  Values of keys in `round2` are compared
  ## after rounding ours to 2 decimal places (as choochoo's ROUND_DISTANCE).
  let us = readCsv(ours)
  var them = readCsv(theirs)
  if them.len > 0: them.delete(0)
  # as choochoo's EXC_HDR_CHK: file header and checksum rows are not compared,
  # and other kinds of data row count as Data
  them.keepItIf(it.len == 0 or it[0] notin ["FileHeader", "Checksum"])
  for row in them.mitems:
    if row.len > 0 and row[0] in ["DeveloperField", "CompressedTimestamp"]:
      row[0] = "Data"
    # older SDK versions name unknown things "MESSAGE n" and "@start:end"
    if row.len > 2 and row[2].startsWith("MESSAGE"): row[2] = "unknown"
    for i in countup(3, row.high, 3):
      if row[i].startsWith("@"): row[i] = "unknown"
  for row in 0 ..< min(us.len, them.len):
    let (a, b) = (us[row], them[row])
    let message = if a.len > 2: a[2] else: ""
    if a.len < 3 or b.len < 3 or a[0 .. 2] != b[0 .. 2]:
      result.add Diff(row: row, kind: dkHeader, message: message,
                      ours: a[0 ..< min(3, a.len)].join(","),
                      theirs: b[0 ..< min(3, b.len)].join(","))
      continue
    let (ta, tb) = (triples(a), triples(b))
    var keys: HashSet[string]
    for k in ta.keys: keys.incl k
    for k in tb.keys: keys.incl k
    for key in keys:
      if key.len == 0 or key == "unknown" or key in ignore: continue
      let ours = ta.getOrDefault(key)
      let theirs = tb.getOrDefault(key)
      if key notin ta:
        if theirs[0].len == 0 or key in composites.getOrDefault(message): continue
        result.add Diff(row: row, kind: dkMissing, message: message, key: key,
                        theirs: theirs[0])
      elif key notin tb:
        if ours[0].len == 0: continue
        result.add Diff(row: row, kind: dkExtra, message: message, key: key,
                        ours: ours[0])
      elif not sameValue(if key in round2: rounded(ours[0]) else: ours[0],
                         theirs[0]):
        result.add Diff(row: row, kind: dkValue, message: message, key: key,
                        ours: ours[0], theirs: theirs[0])
      elif ours[0].len > 0 and ours[1] != theirs[1]:
        result.add Diff(row: row, kind: dkUnits, message: message, key: key,
                        ours: ours[1], theirs: theirs[1])
  if us.len != them.len:
    result.add Diff(row: min(us.len, them.len), kind: dkRowCount,
                    ours: $us.len, theirs: $them.len)

# --- the files that have SDK CSVs

const
  testRoot* = "../choochoo/data/test/"
  csvDirs* = ["sdk", "personal", "python-fitparse", "other"]

type SdkPair* = object
  dir*, name*: string          ## eg "sdk", "Activity.fit"
  fitPath*, csvPath*: string

proc sdkPairs*(): seq[SdkPair] =
  ## Every .fit file under source/ that has a CSV under target/.
  for dir in csvDirs:
    for path in walkFiles(testRoot & "source/" & dir & "/*"):
      let (_, name, ext) = splitFile(path)
      if ext.toLowerAscii != ".fit": continue
      for candidate in [name & ".csv", name & ext & ".csv"]:
        let csv = testRoot & "target/" & dir & "/" & candidate
        if fileExists(csv):
          result.add SdkPair(dir: dir, name: name & ext, fitPath: path,
                             csvPath: csv)
          break
  result.sort(proc (a, b: SdkPair): int = cmp(a.dir & a.name, b.dir & b.name))

# per-file fields to ignore, with the reason
const ignoredFields* = {
  "Activity.fit": @["timer_trigger"],  # choochoo: the SDK value makes no sense
}.toTable

# --- allowed differences

type Allowed* = object
  ## A known, intentional difference.  Only `dirs` are allowed to differ this
  ## way (sdk/ and personal/ must match exactly).
  dirs*: seq[string]
  message*, key*: string
  kinds*: set[DiffKind]
  reason*: string

const older = "older SDK version than Profile.xlsx"
const allowed* = [
  Allowed(dirs: @["python-fitparse", "other"], message: "lap",
          key: "total_cycles", kinds: {dkMissing},
          reason: older & ": cycling laps use total_cycles, we use total_strokes"),
  Allowed(dirs: @["python-fitparse", "other"], message: "lap",
          key: "total_strokes", kinds: {dkExtra},
          reason: older & ": cycling laps use total_cycles, we use total_strokes"),
  Allowed(dirs: @["python-fitparse", "other"], message: "session",
          key: "total_cycles", kinds: {dkMissing},
          reason: older & ": cycling sessions use total_cycles, we use total_strokes"),
  Allowed(dirs: @["python-fitparse", "other"], message: "session",
          key: "total_strokes", kinds: {dkExtra},
          reason: older & ": cycling sessions use total_cycles, we use total_strokes"),
  Allowed(dirs: @["python-fitparse", "other"], message: "session",
          key: "num_lengths", kinds: {dkExtra},
          reason: older & ": field not in its profile (shown as unknown)"),
  Allowed(dirs: @["python-fitparse", "other"], message: "event",
          key: "timer_trigger", kinds: {dkValue},
          reason: "data and data16 both give timer_trigger; the SDK merges them " &
                  "into one array (0|0), we keep two entries (cf choochoo merge_duplicates)"),
]

# per-file fields compared after rounding to 2 decimal places (as choochoo's
# ROUND_DISTANCE: the CSV was written by an older SDK that rounded)
const roundedFields* = {
  "compressed-speed-distance.fit": @["distance"],
}.toTable

proc isAllowed*(dir: string, d: Diff): int =
  ## Index into `allowed` of the entry that covers `d`, or -1.
  for i, a in allowed:
    if dir in a.dirs and d.message == a.message and d.key == a.key and
        d.kind in a.kinds:
      return i
  -1
