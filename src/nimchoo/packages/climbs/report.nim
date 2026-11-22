## What `nch climbs` shows: the rows (from the tables, after `ensureClimbs`) and the lines made from
## them.  Distances are metres in the database and kilometres on the screen; a time is gate to
## gate, stops included.  The formatting is pure.

import std/[options, sequtils, strutils, tables, unicode]
import ../../core/ruled
import ../db/statement
import ../db/store
import ../../core/errors
import ../ui/[markup, style]
import ./[describe, display, work]
import ../text/fold/fold
import ../ui/units

{.push raises: [].}

type SectorRow* = object
  id*: int64
  lengthM*, gainM*, gradient*: float
  category*: Option[string]
  name*: string ## as shown: "name₃", "unnamed" if it has none
  efforts*: int
  manual*: bool ## the name was given by a person
  retired*: bool ## hidden from the lists

# --- the rows

proc shownNames*(st: Store): Table[int64, string] {.raises: [StoreError].} =
  ## The name of every sector as it is shown, "name₃" where a name is shared (the number is kept: see ordinal.nim).
  let climbs =
    st.db.query(Shown, "select id, coalesce(name, ''), name_n from sector order by id")
  let texts = displayNames(climbs)
  for i, c in climbs:
    result[c.id] = texts[i]

type NamedClimbs* = tuple[text: string, ids: seq[int64]]
  ## the climbs a text typed by the user meant (none: no climb has it)

proc climbsNamed*(
    st: Store, texts: seq[string], retiredToo: bool
): seq[NamedClimbs] {.raises: [StoreError].} =
  ## Match typed texts to climbs: the one rule for `climbs --names` and `activities --climbs`.  A climb's name as shown
  ## ("Farellones₂") holds the text, case and accents ignored ("farellones 2" and "farellones2" mean "farellones₂": `ordinalForms`);
  ## a text no name holds that is a whole number is a climb's number (`climbNumber`).  Retired climbs only with `retiredToo`.
  ## The ids of each text are the biggest climb first.
  let names = shownNames(st)
  let ids = st.db.query(
    int64,
    "select id from sector where " & (if retiredToo: "1" else: "retired = 0") &
      " order by gain_m desc, id",
  )
  for t in texts:
    let wanted = ordinalForms(t).mapIt(foldText(it))
    var hits: seq[int64]
    for id in ids:
      let shown = foldText(names.getOrDefault(id, ""))
      if wanted.anyIt(it in shown):
        hits.add id
    if hits.len == 0:
      let n = climbNumber(t)
      if n.isSome and n.get in ids:
        hits.add n.get
    result.add (t, hits)

proc countRetired*(st: Store): int {.raises: [StoreError].} =
  ## How many climbs are retired (hidden).
  st.db.scalar(int, "select count(*) from sector where retired = 1")

proc countLive*(st: Store): int {.raises: [StoreError].} =
  ## How many climbs are not retired (those a list is chosen from).
  st.db.scalar(int, "select count(*) from sector where retired = 0")

proc allSectors*(st: Store, retired = false): seq[SectorRow] {.raises: [StoreError].} =
  ## The sectors that are not retired (or, with `retired`, only those that are), the biggest climb first.  The names are
  ## numbered among all of them, retired ones too.
  let names = shownNames(st)
  for r in st.db.query(
    SectorRow,
    """select s.id, s.length_m, s.gain_m, s.gradient, s.category, '',
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
    name: string, category: Option[string], lengthM, gainM, gradient: float
): ClimbInfo =
  ## The description of a climb (see ClimbInfo) from its columns.
  ClimbInfo(
    name: cut(name),
    category: category,
    lengthM: lengthM,
    gainM: gainM,
    gradient: gradient,
  )

func sectorLines*(rows: seq[SectorRow], width: int): seq[Line] =
  ## A table of the climbs with a line of headings: each the standard way, then how often it was ridden, and "manual"
  ## against a name given by a person.  Only the climbs: how the rides went is `nch climbs` (and -v).
  var cells: seq[seq[string]]
  for s in rows:
    cells.add climbCells(climbOf(s.name, s.category, s.lengthM, s.gainM, s.gradient)) &
      @[$s.efforts, (if s.manual: "manual" else: "")]
  ruled(
    @["climb", "cat", "length", "gain", "gradient", "efforts", ""],
    cells,
    width,
    right = {2, 3, 4, 5, 6},
  )

# --- the display while the climbs are worked out

func climbingLines*(done, total: int, worked: Worked): seq[Line] =
  ## The two lines that follow the work, as the import's do: the first plain ("climbing" emphasised), the second
  ## the counts good, joined by hidden dots.  The last frame is left on the screen.
  ##
  ##     climbing 120 / 1,986 activities
  ##     climbs 12 · efforts 40
  let (d, t) = (count(done), count(total))
  let (c, e) = (count(worked.sectors), count(worked.efforts))
  @[
    ~"<em climbing {d}> / {t} activities",
    ~"<good climbs {c}><hide  · ><good efforts {e}>",
  ]

func workedText*(worked: Worked): string =
  ## What was worked out, in words: "1,986 activities: 161 new climbs, 3,635 efforts".
  count(worked.activities) &
    (if worked.activities == 1: " activity: " else: " activities: ") &
    count(worked.sectors) &
    (if worked.sectors == 1: " new climb, " else: " new climbs, ") &
    counted(worked.efforts, "effort", "efforts")
