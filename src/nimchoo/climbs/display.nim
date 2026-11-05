## How a climb is shown by name.  Names need not be unique: climbs that share a name (without regard to case)
## are shown "name (n/m)", n the rank by gain (the biggest is 1, ties by id) among the m that share it, and only
## when m > 1.  Worked out when shown, never stored, so the numbers close up by themselves when a climb is
## renamed or removed.  A climb with no name is "unnamed".

import std/[algorithm, strutils, tables, unicode]

{.push raises: [].}

const unnamed* = "unnamed"

type Shown* = object
  id*: int64
  name*: string      ## "" if it has none
  gainM*: float

func baseName(name: string): string =
  if name.strip.len == 0: unnamed else: name.strip

func groupKey(name: string): string = baseName(name).toLower

func displayNames*(climbs: openArray[Shown]): seq[string] =
  ## One text per climb, in the order given.
  var groups = initTable[string, seq[int]]()      # key -> positions in `climbs`
  for i, c in climbs:
    groups.mgetOrPut(groupKey(c.name), @[]).add i
  result = newSeq[string](climbs.len)
  for _, members in groups:
    var ranked = newSeq[(float, int64, int)]()          # (gain, id, position)
    for i in members: ranked.add (climbs[i].gainM, climbs[i].id, i)
    ranked.sort(proc (a, b: (float, int64, int)): int =
      result = cmp(b[0], a[0])                           # biggest gain first
      if result == 0: result = cmp(a[1], b[1]))
    for n, r in ranked:
      let base = baseName(climbs[r[2]].name)
      result[r[2]] = if ranked.len > 1: base & " (" & $(n + 1) & "/" & $ranked.len & ")" else: base
