## What `nch climbs` shows: the rows (from the tables, after `ensureClimbs`) and the lines made from
## them.  Distances are metres in the database and kilometres on the screen; a time is gate to
## gate, stops included.  The formatting is pure.

import std/[options, strutils, times]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../ids
import ../ui/style
import ./work

{.push raises: [].}

type
  EffortRow* = object
    ## One pass of a selected activity over a sector, with where it ranks among all passes.
    activity*: int64
    startT*: int64                 ## when the activity began (Unix seconds)
    sport*: string
    distanceM*: Option[float]      ## of the whole activity
    sector*: int64
    atM*: float                    ## metres along the activity where the climb began
    lengthM*, gainM*, gradient*: float
    category*: string              ## "" if none
    name*: string                  ## "" if it has none
    elapsed*: float                ## seconds
    rank*, total*: int             ## 1 for the fastest; of all efforts on the sector, by everyone
    best*: float                   ## the fastest, seconds

  SectorRow* = object
    id*: int64
    lengthM*, gainM*, gradient*: float
    category*: string
    name*: string                  ## "" if it has none
    efforts*: int
    best*: Option[float]           ## the fastest effort, seconds
    by*: string                    ## whose it was
    yours*: Option[float]          ## the best of the user asking

# --- the rows

func num(s: string): float {.raises: [ValueError].} = parseFloat(s)

proc selectedActivities*(st: Store): int {.raises: [StoreError].} =
  ## How many activities the user has selected.
  guard:
    try: result = parseInt(st.db.getValue(sql"select count(*) from selection where user_id = ?", st.userId))
    except ValueError: raiseStore("a bad count")

proc selectedEfforts*(st: Store): seq[EffortRow] {.raises: [StoreError].} =
  ## The efforts of the user's selected activities, in the order of the rides and then along each.
  guard:
    for r in st.db.fastRows(sql"""
        select a.id, a.start_t, coalesce(a.sport, ''), a.distance_m, e.sector_id, e.start_m,
               s.length_m, s.gain_m, s.gradient, coalesce(s.category, ''), coalesce(s.name, ''), e.elapsed_s,
               (select count(*) from effort x where x.sector_id = e.sector_id and x.elapsed_s < e.elapsed_s) + 1,
               (select count(*) from effort x where x.sector_id = e.sector_id),
               (select min(x.elapsed_s) from effort x where x.sector_id = e.sector_id)
          from effort e
          join sector s on s.id = e.sector_id
          join activity a on a.id = e.activity_id
         where a.id in (select activity_id from selection where user_id = ?)
         order by a.start_t, a.id, e.start_t""", st.userId):
      try:
        result.add EffortRow(activity: parseBiggestInt(r[0]), startT: parseBiggestInt(r[1]), sport: r[2],
                             distanceM: (if r[3].len > 0: some(num(r[3])) else: none(float)),
                             sector: parseBiggestInt(r[4]), atM: num(r[5]), lengthM: num(r[6]),
                             gainM: num(r[7]), gradient: num(r[8]), category: r[9], name: r[10],
                             elapsed: num(r[11]), rank: parseInt(r[12]), total: parseInt(r[13]), best: num(r[14]))
      except ValueError:
        raiseStore("a bad number in the climbs")

proc allSectors*(st: Store): seq[SectorRow] {.raises: [StoreError].} =
  ## Every sector, the biggest climb first, with the best time and the user's own.
  guard:
    for r in st.db.fastRows(sql"""
        select s.id, s.length_m, s.gain_m, s.gradient, coalesce(s.category, ''), coalesce(s.name, ''),
               (select count(*) from effort e where e.sector_id = s.id),
               (select min(e.elapsed_s) from effort e where e.sector_id = s.id),
               coalesce((select u.name from effort e join activity a on a.id = e.activity_id
                           join file f on f.id = a.file_id join user u on u.id = f.user_id
                          where e.sector_id = s.id order by e.elapsed_s limit 1), ''),
               (select min(e.elapsed_s) from effort e join activity a on a.id = e.activity_id
                  join file f on f.id = a.file_id where e.sector_id = s.id and f.user_id = ?)
          from sector s order by s.gain_m desc, s.id""", st.userId):
      try:
        result.add SectorRow(id: parseBiggestInt(r[0]), lengthM: num(r[1]), gainM: num(r[2]),
                             gradient: num(r[3]), category: r[4], name: r[5], efforts: parseInt(r[6]),
                             best: (if r[7].len > 0: some(num(r[7])) else: none(float)), by: r[8],
                             yours: (if r[9].len > 0: some(num(r[9])) else: none(float)))
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

func km*(metres: float): string =
  ## Metres as kilometres to a tenth: "14.5".
  formatFloat(metres / 1000.0, ffDecimal, 1)

func columns(rows: seq[seq[string]], right: set[0 .. 31]): seq[string] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right.
  var widths: seq[int]
  for row in rows:
    for c, cell in row:
      if c >= widths.len: widths.add 0
      widths[c] = max(widths[c], cell.len)
  for row in rows:
    var line = ""
    for c, cell in row:
      if c > 0: line.add "  "
      line.add (if c <= 31 and c in right: cell.align(widths[c]) else: cell.alignLeft(widths[c]))
    result.add line.strip(leading = false)

func effortCells(e: EffortRow): seq[string] =
  @["#" & $e.sector, "at " & km(e.atM) & " km", km(e.lengthM) & " km", "+" & $int(e.gainM + 0.5) & " m",
    formatFloat(e.gradient, ffDecimal, 1) & " %", (if e.category.len > 0: "cat " & e.category else: ""),
    duration(e.elapsed), $e.rank & " of " & $e.total, "best " & duration(e.best), e.name]

proc effortLines*(rows: seq[EffortRow], zone: Timezone): seq[string] =
  ## For each activity (as it was picked) a line, then a line for each climb it went up.
  var cells: seq[seq[string]]
  for e in rows: cells.add effortCells(e)
  let aligned = columns(cells, {1, 2, 3, 4, 6, 7, 8})
  var last = -1'i64
  for i, e in rows:
    if e.activity != last:
      last = e.activity
      var head = fromUnix(e.startT).inZone(zone).format("yyyy-MM-dd HH:mm")
      if e.sport.len > 0: head.add "  " & e.sport
      if e.distanceM.isSome: head.add "  " & km(e.distanceM.get) & " km"
      result.add head
    result.add "  " & aligned[i]

func sectorLines*(rows: seq[SectorRow]): seq[string] =
  ## A table of the sectors with a line of headings.
  var cells = @[@["climb", "length", "gain", "gradient", "cat", "efforts", "best", "by", "yours", "name"]]
  for s in rows:
    cells.add @["#" & $s.id, km(s.lengthM) & " km", "+" & $int(s.gainM + 0.5) & " m",
                formatFloat(s.gradient, ffDecimal, 1) & " %", s.category, $s.efforts,
                (if s.best.isSome: duration(s.best.get) else: ""), s.by,
                (if s.yours.isSome: duration(s.yours.get) else: ""), s.name]
  columns(cells, {1, 2, 3, 5, 6, 8})

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
