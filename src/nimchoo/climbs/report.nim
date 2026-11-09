## What `nch climbs` shows: the rows (from the tables, after `ensureClimbs`) and the lines made from
## them.  Distances are metres in the database and kilometres on the screen; a time is gate to
## gate, stops included.  The formatting is pure.

import std/[strutils, tables, unicode]
import ../db/[statement, store]
import ../core/errors
import ../ui/style
import ./[describe, display, work]

{.push raises: [].}

type SectorRow* = object
  id*: int64
  lengthM*, gainM*, gradient*: float
  category*: string
  name*: string ## as shown: "name₃", "unnamed" if it has none
  efforts*: int
  manual*: bool ## the name was given by a person
  retired*: bool ## hidden from the lists

# --- the rows

proc selectedActivities*(st: Store): int {.raises: [StoreError].} =
  ## How many activities the user has selected.
  st.db.scalar(
    int, "select count(*) from selection where user_id = :userId", userId = st.userId
  )

proc shownNames*(st: Store): Table[int64, string] {.raises: [StoreError].} =
  ## The name of every sector as it is shown, "name₃" where a name is shared (the number is kept: see ordinal.nim).
  let climbs =
    st.db.query(Shown, "select id, coalesce(name, ''), name_n from sector order by id")
  let texts = displayNames(climbs)
  for i, c in climbs:
    result[c.id] = texts[i]

proc countRetired*(st: Store): int {.raises: [StoreError].} =
  ## How many climbs are retired (hidden).
  st.db.scalar(int, "select count(*) from sector where retired = 1")

proc allSectors*(st: Store, retired = false): seq[SectorRow] {.raises: [StoreError].} =
  ## The sectors that are not retired (or, with `retired`, only those that are), the biggest climb first.  The names are
  ## numbered among all of them, retired ones too.
  let names = shownNames(st)
  for r in st.db.query(
    SectorRow,
    """select s.id, s.length_m, s.gain_m, s.gradient, coalesce(s.category, ''), '',
              (select count(*) from effort e where e.sector_id = s.id), s.manual, s.retired
         from sector s where s.retired = :retired order by s.gain_m desc, s.id""",
    retired = retired,
  ):
    var row = r
    row.name = names.getOrDefault(r.id, unnamed)
    result.add row

# --- the lines

func duration*(seconds: float): string =
  ## "9:12", "1:02:03" (to the second).
  let total = int(seconds + 0.5)
  let h = total div 3600
  let m = (total mod 3600) div 60
  let s = total mod 60
  if h > 0:
    $h & ":" & align($m, 2, '0') & ":" & align($s, 2, '0')
  else:
    $m & ":" & align($s, 2, '0')

func columns*(rows: seq[seq[string]], right: set[0 .. 31]): seq[string] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right.
  var widths: seq[int]
  for row in rows:
    for c, cell in row:
      if c >= widths.len:
        widths.add 0
      widths[c] = max(widths[c], cell.runeLen)
  for row in rows:
    var line = ""
    for c, cell in row:
      if c > 0:
        line.add "  "
      let pad = repeat(' ', widths[c] - cell.runeLen)
      line.add (if c <= 31 and c in right: pad & cell
      else: cell & pad)
    result.add line.strip(leading = false)

const nameWidth* = 30

func cut*(name: string, width = nameWidth): string =
  ## A name no wider than `width` characters; a longer one ends in "...", but a trailing subscript number is kept.
  if name.runeLen <= width:
    return name
  var base = name
  var suffix = ""
  if endsWithSubscript(name):
    base = withoutSubscript(name)
    suffix = name[base.len .. ^1]
  let room = width - suffix.runeLen
  if room < 4 or base.runeLen <= room:
    name.runeSubStr(0, width - 3) & "..."
  else:
    base.runeSubStr(0, room - 3) & "..." & suffix

func climbOf*(
    name: string, category: string, lengthM, gainM, gradient: float
): ClimbInfo =
  ## The description of a climb (see ClimbInfo) from its columns.
  ClimbInfo(
    name: cut(name),
    category: category,
    lengthM: lengthM,
    gainM: gainM,
    gradient: gradient,
  )

func sectorLines*(rows: seq[SectorRow]): seq[string] =
  ## A table of the climbs with a line of headings: each the standard way, then how often it was ridden, and "manual"
  ## against a name given by a person.  Only the climbs: how the rides went is `nch climbs` (and -v).
  var cells = @[@["climb", "cat", "length", "gain", "gradient", "efforts", ""]]
  for s in rows:
    cells.add climbCells(climbOf(s.name, s.category, s.lengthM, s.gainM, s.gradient)) &
      @[$s.efforts, (if s.manual: "manual" else: "")]
  columns(cells, {2, 3, 4, 5, 6})

# --- the display while the climbs are worked out

func commas(n: int): string =
  insertSep($n, ',')

func climbingLines*(done, total: int, worked: Worked): seq[Line] =
  ## The two lines that follow the work, as the import's do: the first plain ("climbing" in bold), the second
  ## the counts in green, joined by grey dots.  The last frame is left on the screen.
  ##
  ##     climbing 120 / 1,986 activities
  ##     climbs 12 · efforts 40
  @[
    @[
      span("climbing ", bold = true),
      span(commas(done) & " / " & commas(total) & " activities"),
    ],
    @[
      span("climbs " & commas(worked.sectors), green),
      span(" · ", grey),
      span("efforts " & commas(worked.efforts), green),
    ],
  ]

func doneLine*(worked: Worked): string =
  ## The line after the display, as the import's: "done: 1,986 activities: 161 new climbs, 3,635 efforts".
  "done: " & commas(worked.activities) &
    (if worked.activities == 1: " activity: " else: " activities: ") &
    commas(worked.sectors) &
    (if worked.sectors == 1: " new climb, " else: " new climbs, ") &
    commas(worked.efforts) & (if worked.efforts == 1: " effort" else: " efforts")
