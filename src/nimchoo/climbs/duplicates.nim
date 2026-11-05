## Climbs that are largely the same: sectors of which more than half of each lies within 25 m of the other (the test
## `match.isRepeat` uses when it looks for a climb that is stored already).  A ride that stops a little short of a climb's
## finish makes a climb of its own (see work.nim), so these happen.  The report puts them in groups, the most ridden
## first, and offers to hide a climb only if it overlaps a more ridden one directly (a group can be a chain of climbs, from
## rides that turn round in different places, which are not all copies of the most ridden).  Retiring is by hand
## (`nch sector --edit NAME --retire`).

import std/[algorithm, strutils, tables]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ./[describe, display, match, report]

{.push raises: [].}

type
  Member* = object
    id*: int64
    name*: string                  ## as shown ("name (n/m)")
    category*: string
    lengthM*, gainM*, gradient*: float
    efforts*: int
    retired*: bool
    hideable*: bool                ## it overlaps (directly) a climb that has more efforts, so it may be a duplicate of it

  Group* = object
    members*: seq[Member]          ## the most ridden first

func pathOf(text: string): Path =
  ## The positions of "LINESTRING Z(lon lat alt, ...)".
  let a = text.find('(')
  let b = text.rfind(')')
  if a < 0 or b <= a: return
  try:
    for part in text[a + 1 ..< b].split(','):
      let f = part.splitWhitespace
      if f.len < 2: return Path()
      result.lon.add parseFloat(f[0])
      result.lat.add parseFloat(f[1])
  except ValueError:
    result = Path()

proc duplicateGroups*(st: Store): seq[Group] {.raises: [StoreError].} =
  ## Groups of two or more sectors that largely overlap (a sector that overlaps one of a group joins it), retired ones too.
  let names = shownNames(st)
  var members: seq[Member]
  var paths: seq[Path]
  guard:
    for r in st.db.fastRows(sql"""select s.id, s.length_m, s.gain_m, AsText(s.route), s.retired,
        (select count(*) from effort e where e.sector_id = s.id), coalesce(s.category, ''), s.gradient
        from sector s order by s.id"""):
      try:
        let id = parseBiggestInt(r[0])
        members.add Member(id: id, name: names.getOrDefault(id, unnamed), lengthM: parseFloat(r[1]),
                           gainM: parseFloat(r[2]), efforts: parseInt(r[5]), retired: r[4] == "1",
                           category: r[6], gradient: parseFloat(r[7]))
        paths.add pathOf(r[3])
      except ValueError:
        raiseStore("a bad number in the climbs")
  # groups by union: a climb that overlaps one in a group is in it
  var parent = newSeq[int](members.len)
  for i in 0 ..< parent.len: parent[i] = i
  var hideable = newSeq[bool](members.len)
  proc root(i: int): int =
    var k = i
    while parent[k] != k: k = parent[k]
    k
  for i in 0 ..< members.len:
    for j in i + 1 ..< members.len:
      if isRepeat(paths[i], paths[j]):
        let a = root(i)
        let b = root(j)
        if a != b: parent[b] = a
        if members[j].efforts > members[i].efforts: hideable[i] = true
        if members[i].efforts > members[j].efforts: hideable[j] = true
  var byRoot = initOrderedTable[int, seq[Member]]()
  for i in 0 ..< members.len:
    members[i].hideable = hideable[i]
    byRoot.mgetOrPut(root(i), @[]).add members[i]
  for _, ms in byRoot:
    if ms.len < 2: continue
    var g = Group(members: ms)
    g.members.sort(proc (a, b: Member): int =
      result = cmp(b.efforts, a.efforts)
      if result == 0: result = cmp(a.id, b.id))
    result.add g
  result.sort(proc (a, b: Group): int =
    var ea, eb = 0
    for m in a.members: ea += m.efforts
    for m in b.members: eb += m.efforts
    result = cmp(eb, ea))

func duplicateLines*(groups: seq[Group]): seq[string] =
  ## The groups, each a block of lines: the climbs with their length, gain and efforts, the most ridden first, and the
  ## command to hide one.
  if groups.len == 0: return @["no climbs overlap: nothing to tidy"]
  result.add "climbs that largely overlap (more than half of each is within 25 m of the other), the most ridden first:"
  for g in groups:
    result.add ""
    var cells: seq[seq[string]]
    for m in g.members:
      cells.add climbCells(ClimbInfo(name: cut(m.name), category: m.category, lengthM: m.lengthM, gainM: m.gainM,
                                     gradient: m.gradient)) &
                @[$m.efforts & (if m.efforts == 1: " effort" else: " efforts"), (if m.retired: "retired" else: "")]
    for l in columns(cells, {2, 3, 4, 5}): result.add "  " & l
    for m in g.members:
      if m.hideable and not m.retired:
        result.add "    hide: nch sector --edit \"" & m.name & "\" --retire   (overlaps a climb with more efforts)"
