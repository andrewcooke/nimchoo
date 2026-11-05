## What `nch climbs` shows: the rows (from the tables, after `ensureClimbs`) and the lines made from
## them.  Distances are metres in the database and kilometres on the screen; a time is gate to
## gate, stops included.  The formatting is pure.

import std/[options, strutils, tables, times, unicode]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../describe
import ../fit/time
import ../ids
import ../ui/style
import ./[display, work]

{.push raises: [].}

type
  EffortRow* = object
    ## One pass of a selected activity over a sector, with where it ranks among all passes.
    activity*: int64
    startT*: int64                 ## when the activity began (Unix seconds)
    sport*: string
    distanceM*: Option[float]      ## of the whole activity
    activeS*: Option[float]        ## the time its timer ran
    place*, activityName*: string  ## where it started and what it is called ("" if nothing)
    sector*: int64
    atM*: float                    ## metres along the activity where the climb began
    lengthM*, gainM*, gradient*: float
    category*: string              ## "" if none
    name*: string                  ## as shown: "name (n/m)", "unnamed" if it has none
    elapsed*: float                ## seconds
    rank*, total*: int             ## 1 for the fastest; of all efforts on the sector, by everyone
    best*: float                   ## the fastest, seconds

  SectorRow* = object
    id*: int64
    lengthM*, gainM*, gradient*: float
    category*: string
    name*: string                  ## as shown: "name (n/m)", "unnamed" if it has none
    efforts*: int
    best*: Option[float]           ## the fastest effort, seconds
    by*: string                    ## whose it was
    yours*: Option[float]          ## the best of the user asking
    manual*: bool                  ## the name was given by a person
    retired*: bool                 ## hidden from the lists

# --- the rows

func num(s: string): float {.raises: [ValueError].} = parseFloat(s)

proc selectedActivities*(st: Store): int {.raises: [StoreError].} =
  ## How many activities the user has selected.
  guard:
    try: result = parseInt(st.db.getValue(sql"select count(*) from selection where user_id = ?", st.userId))
    except ValueError: raiseStore("a bad count")

proc shownNames*(st: Store): Table[int64, string] {.raises: [StoreError].} =
  ## The name of every sector as it is shown, "name (n/m)" where a name is shared (ranked by gain).
  var climbs: seq[Shown]
  guard:
    for r in st.db.fastRows(sql"select id, coalesce(name, ''), gain_m from sector order by id"):
      try: climbs.add Shown(id: parseBiggestInt(r[0]), name: r[1], gainM: num(r[2]))
      except ValueError: raiseStore("a bad number in the climbs")
  let texts = displayNames(climbs)
  for i, c in climbs: result[c.id] = texts[i]

proc selectedEfforts*(st: Store): seq[EffortRow] {.raises: [StoreError].} =
  ## The efforts of the user's selected activities, in the order of the rides and then along each.
  let names = shownNames(st)
  guard:
    for r in st.db.fastRows(sql"""
        select a.id, a.start_t, coalesce(a.sport, ''), a.distance_m, e.sector_id, e.start_m,
               s.length_m, s.gain_m, s.gradient, coalesce(s.category, ''), e.elapsed_s,
               (select count(*) from effort x where x.sector_id = e.sector_id and x.elapsed_s < e.elapsed_s) + 1,
               (select count(*) from effort x where x.sector_id = e.sector_id),
               (select min(x.elapsed_s) from effort x where x.sector_id = e.sector_id),
               a.timer_s, coalesce(a.start_place, ''), coalesce(a.name, '')
          from effort e
          join sector s on s.id = e.sector_id
          join activity a on a.id = e.activity_id
         where a.id in (select activity_id from selection where user_id = ?) and s.retired = 0
         order by a.start_t, a.id, e.start_t""", st.userId):
      try:
        result.add EffortRow(activity: parseBiggestInt(r[0]), startT: parseBiggestInt(r[1]), sport: r[2],
                             distanceM: (if r[3].len > 0: some(num(r[3])) else: none(float)),
                             sector: parseBiggestInt(r[4]), atM: num(r[5]), lengthM: num(r[6]),
                             gainM: num(r[7]), gradient: num(r[8]), category: r[9],
                             name: names.getOrDefault(parseBiggestInt(r[4]), unnamed),
                             elapsed: num(r[10]), rank: parseInt(r[11]), total: parseInt(r[12]), best: num(r[13]),
                             activeS: (if r[14].len > 0: some(num(r[14])) else: none(float)), place: r[15], activityName: r[16])
      except ValueError:
        raiseStore("a bad number in the climbs")

proc countRetired*(st: Store): int {.raises: [StoreError].} =
  ## How many climbs are retired (hidden).
  guard:
    try: result = parseInt(st.db.getValue(sql"select count(*) from sector where retired = 1"))
    except ValueError: raiseStore("a bad count")

proc allSectors*(st: Store, retired = false): seq[SectorRow] {.raises: [StoreError].} =
  ## The sectors that are not retired (or, with `retired`, only those that are), the biggest climb first, with the best
  ## time and the user's own.  The names are numbered among all of them, retired ones too.
  let names = shownNames(st)
  guard:
    for r in st.db.fastRows(sql"""
        select s.id, s.length_m, s.gain_m, s.gradient, coalesce(s.category, ''),
               (select count(*) from effort e where e.sector_id = s.id),
               (select min(e.elapsed_s) from effort e where e.sector_id = s.id),
               coalesce((select u.name from effort e join activity a on a.id = e.activity_id
                           join file f on f.id = a.file_id join user u on u.id = f.user_id
                          where e.sector_id = s.id order by e.elapsed_s limit 1), ''),
               (select min(e.elapsed_s) from effort e join activity a on a.id = e.activity_id
                  join file f on f.id = a.file_id where e.sector_id = s.id and f.user_id = ?),
               s.manual, s.retired
          from sector s where s.retired = ? order by s.gain_m desc, s.id""", st.userId, (if retired: 1 else: 0)):
      try:
        result.add SectorRow(id: parseBiggestInt(r[0]), lengthM: num(r[1]), gainM: num(r[2]),
                             gradient: num(r[3]), category: r[4], name: names.getOrDefault(parseBiggestInt(r[0]), unnamed),
                             efforts: parseInt(r[5]),
                             best: (if r[6].len > 0: some(num(r[6])) else: none(float)), by: r[7],
                             yours: (if r[8].len > 0: some(num(r[8])) else: none(float)), manual: r[9] == "1",
                             retired: r[10] == "1")
      except ValueError:
        raiseStore("a bad number in the climbs")

# --- the lines

func duration*(seconds: float): string =
  ## "9:12", "1:02:03" (to the second).
  let total = int(seconds + 0.5)
  let h = total div 3600
  let m = (total mod 3600) div 60
  let s = total mod 60
  if h > 0: $h & ":" & align($m, 2, '0') & ":" & align($s, 2, '0')
  else: $m & ":" & align($s, 2, '0')

func columns*(rows: seq[seq[string]], right: set[0 .. 31]): seq[string] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right.
  var widths: seq[int]
  for row in rows:
    for c, cell in row:
      if c >= widths.len: widths.add 0
      widths[c] = max(widths[c], cell.runeLen)
  for row in rows:
    var line = ""
    for c, cell in row:
      if c > 0: line.add "  "
      let pad = repeat(' ', widths[c] - cell.runeLen)
      line.add (if c <= 31 and c in right: pad & cell else: cell & pad)
    result.add line.strip(leading = false)

const nameWidth* = 30

func cut*(name: string, width = nameWidth): string =
  ## A name no wider than `width` characters; a longer one ends in "...", but a trailing " (n/m)" is kept.
  if name.runeLen <= width: return name
  var base = name
  var suffix = ""
  let open = name.rfind(" (")
  if open > 0 and name.endsWith(")") and '/' in name[open .. ^1]:
    base = name[0 ..< open]
    suffix = name[open .. ^1]
  let room = width - suffix.runeLen
  if room < 4 or base.runeLen <= room: name.runeSubStr(0, width - 3) & "..."
  else: base.runeSubStr(0, room - 3) & "..." & suffix

func climbOf(name: string, category: string, lengthM, gainM, gradient: float): ClimbInfo =
  ClimbInfo(name: cut(name), category: category, lengthM: lengthM, gainM: gainM, gradient: gradient)

func effortCells(e: EffortRow): seq[string] =
  ## The climb the standard way (name, category, length, gain, gradient), then where on the ride it began and how it went.
  climbCells(climbOf(e.name, e.category, e.lengthM, e.gainM, e.gradient)) &
    @["at " & km(e.atM), duration(e.elapsed), $e.rank & " of " & $e.total, "best " & duration(e.best)]

proc effortLines*(rows: seq[EffortRow], zone: Timezone): seq[string] =
  ## For each activity (as it was picked, described the standard way) a line, then a line for each climb it went up.
  var cells: seq[seq[string]]
  for e in rows: cells.add effortCells(e)
  let aligned = columns(cells, {2, 3, 4, 5, 6, 7, 8})
  var last = -1'i64
  for i, e in rows:
    if e.activity != last:
      last = e.activity
      result.add activityLine(ActivityInfo(startT: UnixTime(e.startT), sport: e.sport, distanceM: e.distanceM,
                                           activeS: e.activeS, place: e.place, name: e.activityName), zone)
    result.add "  " & aligned[i]

func sectorLines*(rows: seq[SectorRow]): seq[string] =
  ## A table of the sectors with a line of headings: each climb the standard way, then how often it was ridden.
  var cells = @[@["climb", "cat", "length", "gain", "gradient", "efforts", "best", "by", "yours"]]
  for s in rows:
    cells.add climbCells(climbOf(s.name, s.category, s.lengthM, s.gainM, s.gradient)) &
      @[$s.efforts, (if s.best.isSome: duration(s.best.get) else: ""), s.by,
        (if s.yours.isSome: duration(s.yours.get) else: "")]
  columns(cells, {2, 3, 4, 5, 6, 8})

# --- the display while the climbs are worked out

func commas(n: int): string = insertSep($n, ',')

func climbingLines*(done, total: int, worked: Worked): seq[Line] =
  ## The two lines that follow the work, as the import's do: the first plain ("climbing" in bold), the second
  ## the counts in green, joined by grey dots.  The last frame is left on the screen.
  ##
  ##     climbing 120 / 1,986 activities
  ##     climbs 12 · efforts 40
  @[@[span("climbing ", bold = true), span(commas(done) & " / " & commas(total) & " activities")],
    @[span("climbs " & commas(worked.sectors), green), span(" · ", grey),
      span("efforts " & commas(worked.efforts), green)]]

func doneLine*(worked: Worked): string =
  ## The line after the display, as the import's: "done: 1,986 activities: 161 new climbs, 3,635 efforts".
  "done: " & commas(worked.activities) & (if worked.activities == 1: " activity: " else: " activities: ") &
    commas(worked.sectors) & (if worked.sectors == 1: " new climb, " else: " new climbs, ") &
    commas(worked.efforts) & (if worked.efforts == 1: " effort" else: " efforts")
