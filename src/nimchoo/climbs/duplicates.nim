## Climbs that are nearly the same: sectors of which at least four fifths of each lies within 25 m of the other
## (`match.isNearCopy`; the looser `isRepeat`, half of each, is for deciding whether a newly found climb is one that is
## stored already, and would join a whole road of nested climbs into one group).  A ride that stops a little short of a
## climb's finish makes a climb of its own (see work.nim), so these happen.  The report puts them in groups, the most
## ridden first, and offers to hide a climb only if it is a near copy of a more ridden one.  Retiring is by hand
## (`nch climbs --edit NAME --retire`).

import std/[algorithm, options, tables]
import ../db/[statement, store]
import ../core/errors
import ./[describe, display, match, report]

{.push raises: [].}

type
  Member* = object
    id*: int64
    name*: string ## as shown ("name₃")
    category*: string
    lengthM*, gainM*, gradient*: float
    efforts*: int
    unique*: int
      ## of the efforts, those of rides that did not match any of its near copies
    copies*: seq[int64]
      ## the ids of the climbs that are near copies of this one (directly)
    retired*: bool
    hideable*: bool
      ## it is a near copy of a climb that has more efforts, so it may be a duplicate of it

  Group* = object
    members*: seq[Member] ## the most ridden first

type DuplicateRow =
  tuple[
    id: int64,
    lengthM, gainM: float,
    route: string,
    retired: bool,
    efforts: int,
    category: string,
    gradient: float,
  ]

proc duplicateGroups*(st: Store): seq[Group] {.raises: [StoreError].} =
  ## Groups of two or more sectors that are near copies of each other (a sector that is a near copy of one of a group
  ## joins it), retired ones too.
  let names = shownNames(st)
  var members: seq[Member]
  var paths: seq[Path]
  for r in st.db.query(
    DuplicateRow,
    """select s.id, s.length_m, s.gain_m, AsText(s.route), s.retired,
         (select count(*) from effort e where e.sector_id = s.id), coalesce(s.category, ''), s.gradient
         from sector s order by s.id""",
  ):
    members.add Member(
      id: r.id,
      name: names.getOrDefault(r.id, unnamed),
      lengthM: r.lengthM,
      gainM: r.gainM,
      efforts: r.efforts,
      retired: r.retired,
      category: r.category,
      gradient: r.gradient,
    )
    let path = parseLineString(r.route)
    if path.isNone:
      raiseStore(
        "climb " & $r.id & " has a route that cannot be read (damaged data): " &
          "run `nch climbs --all --delete -f` and ask for the climbs again"
      )
    paths.add path.get
  # groups by union: a climb that overlaps one in a group is in it
  var parent = newSeq[int](members.len)
  for i in 0 ..< parent.len:
    parent[i] = i
  var hideable = newSeq[bool](members.len)
  var copies = newSeq[seq[int64]](members.len)
  proc root(i: int): int =
    var k = i
    while parent[k] != k:
      k = parent[k]
    k

  for i in 0 ..< members.len:
    for j in i + 1 ..< members.len:
      if isNearCopy(paths[i], paths[j]):
        copies[i].add members[j].id
        copies[j].add members[i].id
        let a = root(i)
        let b = root(j)
        if a != b:
          parent[b] = a
        if members[j].efforts > members[i].efforts:
          hideable[i] = true
        if members[i].efforts > members[j].efforts:
          hideable[j] = true
  var byRoot = initOrderedTable[int, seq[Member]]()
  for i in 0 ..< members.len:
    members[i].hideable = hideable[i]
    members[i].copies = copies[i]
    byRoot.mgetOrPut(root(i), @[]).add members[i]
  for _, ms in byRoot:
    if ms.len < 2:
      continue
    var g = Group(members: ms)
    g.members.sort(
      proc(a, b: Member): int =
        result = cmp(b.efforts, a.efforts)
        if result == 0:
          result = cmp(a.id, b.id)
    )
    # the efforts that are this climb's alone: the ride has no effort on any climb that is a near copy of it
    for m in g.members.mitems:
      m.unique = st.db.scalar(
        int,
        "select count(*) from effort e where e.sector_id = :sectorId and not exists " &
          "(select 1 from effort x where x.activity_id = e.activity_id and " &
          "x.sector_id in (select value from json_each(:ids)))",
        sectorId = m.id,
        ids = jsonList(m.copies),
      )
    result.add g
  result.sort(
    proc(a, b: Group): int =
      var ea, eb = 0
      for m in a.members:
        ea += m.efforts
      for m in b.members:
        eb += m.efforts
      result = cmp(eb, ea)
  )

func duplicateLines*(groups: seq[Group]): seq[string] =
  ## The groups, each a block of lines: the climbs with their length, gain and efforts (and how many of them are unique to
  ## the climb: none of its near copies was matched by that ride), the most ridden first; then, at
  ## the end, one line that shows how to hide a climb (NAME is any of those above that is a copy of one with more efforts).
  if groups.len == 0:
    return @["no climbs overlap: nothing to tidy"]
  result.add "climbs that are nearly the same (at least 80% of each is within 25 m of the other), the most ridden first:"
  var anyToHide = false
  for g in groups:
    result.add ""
    var cells: seq[seq[string]]
    for m in g.members:
      cells.add climbCells(
        ClimbInfo(
          name: cut(m.name),
          category: m.category,
          lengthM: m.lengthM,
          gainM: m.gainM,
          gradient: m.gradient,
        )
      ) &
        @[
          $m.unique & "/" & $m.efforts &
            (if m.efforts == 1: " effort unique" else: " efforts unique"),
          (if m.retired: "retired" else: ""),
        ]
    for l in columns(cells, {2, 3, 4, 5}):
      result.add "  " & l
    for m in g.members:
      if m.hideable and not m.retired:
        anyToHide = true
  if anyToHide:
    result.add ""
    result.add "hide: nch climbs --edit 'NAME' --retire"
      # (NAME: any climb above that is a copy of one with more efforts)
