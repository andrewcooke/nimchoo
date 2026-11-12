## What `nch climbs` shows of the rides over each climb: a summary line a climb, and with -v the attempts under it.
## There are two ranks, and they are never shown together.  The personal rank compares one attempt with the user's own
## attempts on the climb ("3 of 12"); the leaderboard rank compares each person's best time ("4 of 6", with `--everyone`).
## Both are worked out when they are wanted, from the efforts; nothing is stored.
##
## Which climbs are shown is not decided here: the selected rides' climbs, or those whose name holds some text.
## Whatever the climbs, all their attempts count, those of the selected rides and the others.

import std/[algorithm, options, sequtils, strutils, tables, times]
import ../ui/columns
import ../db/statement
import ../db/store
import ../../core/errors
import ../fit/time
import ../importer/describe
import ../util/lookup/lookup
import ../text/fold/fold
import std/unicode
import ../ui/palette
import ../ui/style
import ../ui/units
import ../ui/vocabulary
import ./[describe, display, report]
import ../user/session

{.push raises: [].}

type
  Attempt* = object ## One pass of the user over a climb.
    activity*: ActivityInfo
    elapsed*: float ## seconds, gate to gate
    rank*, total*: int ## the personal rank: 1 for the fastest of the user's own attempts
    selected*: bool ## the ride is one of the selected activities

  Rider* = object ## A person's best time on a climb.
    user*: string
    elapsed*: float
    startT*: int64 ## when the ride began (Unix seconds)
    rank*, total*: int ## the leaderboard rank: 1 for the fastest person
    me*: bool

  Summary* = object
    climb*: ClimbInfo
    attempts*: seq[Attempt] ## the user's, oldest first
    riders*: seq[Rider] ## each person's best, the fastest first

# --- which climbs

proc selectedClimbs*(st: Session): seq[int64] {.raises: [StoreError].} =
  ## The climbs (not retired) that the selected activities went up, the biggest first.
  st.db.query(
    int64,
    "select s.id from sector s where s.retired = 0 and exists (select 1 from effort e " &
      "where e.sector_id = s.id and e.activity_id in " &
      "(select activity_id from selection where user_id = :userId)) order by s.gain_m desc, s.id",
    userId = st.userId,
  )

proc climbsOfActivities*(
    st: Store, activities: seq[int64]
): seq[int64] {.raises: [StoreError].} =
  ## The climbs (not retired) that the activities went up, the biggest first.  (The list is bound as one value, see `jsonList`.)
  if activities.len == 0:
    return
  st.db.query(
    int64,
    "select s.id from sector s where s.retired = 0 and exists (select 1 from effort e " &
      "where e.sector_id = s.id and e.activity_id in (select value from json_each(:ids))) " &
      "order by s.gain_m desc, s.id",
    ids = jsonList(activities),
  )

proc namedClimbs*(st: Store, texts: seq[string]): seq[int64] {.raises: [StoreError].} =
  ## The climbs (not retired) whose name as shown ("Farellones₂") holds any of the texts, case and accents ignored, the
  ## biggest first.  "farellones 2" and "farellones2" mean "farellones₂" as well (`ordinalForms`).  A whole number that
  ## no name holds is a climb's number (`climbNumber`).
  let names = shownNames(st)
  var found: seq[int64]
  let ids = st.db.query(
    int64, "select id from sector where retired = 0 order by gain_m desc, id"
  )
  for t in texts:
    var wanted: seq[string]
    for f in ordinalForms(t):
      wanted.add foldText(f)
    var hits: seq[int64]
    for id in ids:
      let shown = foldText(names.getOrDefault(id, ""))
      if wanted.anyIt(it in shown):
        hits.add id
    if hits.len == 0:
      let n = climbNumber(t)
      if n.isSome and n.get in ids:
        hits.add n.get
    found.add hits
  for id in ids:
    if id in found:
      result.add id

# --- the rows

type
  ClimbRow = tuple[id: int64, lengthM, gainM, gradient: float, category: string]
  AttemptRow =
    tuple[
      sectorId, startT: int64,
      sport, subSport: string,
      distanceM, activeS: Option[float],
      place, name: string,
      elapsed: float,
      selected: bool,
      rank, total: int,
    ]
  BestRow =
    tuple[
      sectorId, userId: int64,
      user: string,
      elapsed: float,
      startT: int64,
      rank, total: int,
    ]

proc summaries*(st: Session, ids: seq[int64]): seq[Summary] {.raises: [StoreError].} =
  ## The climbs `ids`, in that order, with the user's attempts and everyone's best times.  Three queries for all of them
  ## (not three for each): the ranks are the database's (`rank()`: equal times share a rank, the next is one plus the
  ## number of faster times).
  if ids.len == 0:
    return
  let names = shownNames(st)
  let wanted = jsonList(ids)
  var sums = initTable[int64, Summary]()
  for id in ids:
    sums[id] = Summary()
  for r in st.db.query(
    ClimbRow,
    "select id, length_m, gain_m, gradient, coalesce(category, '') from sector " &
      "where id in (select value from json_each(:ids))",
    ids = wanted,
  ):
    sums.mustMut(r.id).climb = climbOf(
      names.getOrDefault(r.id, unnamed), r.category, r.lengthM, r.gainM, r.gradient
    )
  for r in st.db.query(
    AttemptRow,
    """select e.sector_id, a.start_t, coalesce(a.sport, ''), coalesce(a.sub_sport, ''), a.distance_m, a.timer_s,
              coalesce(a.start_place, ''), coalesce(a.name, ''), e.elapsed_s,
              a.id in (select activity_id from selection where user_id = :userId),
              rank() over (partition by e.sector_id order by e.elapsed_s),
              count(*) over (partition by e.sector_id)
         from effort e join activity a on a.id = e.activity_id join file f on f.id = a.file_id
        where e.sector_id in (select value from json_each(:ids)) and f.user_id = :userId
        order by e.sector_id, a.start_t, e.start_t""",
    userId = st.userId,
    ids = wanted,
  ):
    let info = ActivityInfo(
      startT: UnixTime(r.startT),
      sport: r.sport,
      subSport: r.subSport,
      distanceM: r.distanceM,
      activeS: r.activeS,
      place: r.place,
      name: r.name,
    )
    sums.mustMut(r.sectorId).attempts.add Attempt(
      activity: info,
      elapsed: r.elapsed,
      selected: r.selected,
      rank: r.rank,
      total: r.total,
    )
  # each person's best: the fastest time, the earlier ride if two are equal; then the people ranked by it
  for r in st.db.query(
    BestRow,
    """with each as (
         select e.sector_id, f.user_id, u.name, e.elapsed_s, a.start_t,
                row_number() over (partition by e.sector_id, f.user_id order by e.elapsed_s, a.start_t) as n
           from effort e join activity a on a.id = e.activity_id join file f on f.id = a.file_id
           join user u on u.id = f.user_id
          where e.sector_id in (select value from json_each(:ids))),
       best as (select * from each where n = 1)
       select sector_id, user_id, name, elapsed_s, start_t,
              rank() over (partition by sector_id order by elapsed_s),
              count(*) over (partition by sector_id)
         from best order by sector_id, elapsed_s, start_t, user_id""",
    ids = wanted,
  ):
    sums.mustMut(r.sectorId).riders.add Rider(
      user: r.user,
      elapsed: r.elapsed,
      startT: r.startT,
      rank: r.rank,
      total: r.total,
      me: r.userId == int64(st.userId),
    )
  for id in ids:
    result.add sums.must(id)

# --- the lines

func rankText(rank, total: int): string =
  $rank & " of " & $total

proc dateText(startT: int64, zone: Timezone): string =
  dateTimeText(UnixTime(startT), zone)[0 .. 9]

func best(s: Summary, selectedOnly = false): Option[Attempt] =
  ## The user's fastest attempt (the first, if several are equal); with `selectedOnly`, the fastest of those on selected rides.
  for a in s.attempts:
    if selectedOnly and not a.selected:
      continue
    if result.isNone or a.elapsed < result.get.elapsed:
      result = some(a)

func alignedLines(
    cells: seq[seq[string]], right, selectedCols: set[0 .. 31]
): seq[Line] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right, and those in `selectedCols`
  ## in the selection's colour.
  var widths: seq[int]
  for row in cells:
    for c, cell in row:
      if c >= widths.len:
        widths.add 0
      widths[c] = max(widths[c], cell.runeLen)
  for row in cells:
    var line: Line
    for c, cell in row:
      if c > 0:
        line.add span("  ")
      let pad = repeat(' ', widths[c] - cell.runeLen)
      let text =
        if c <= 31 and c in right:
          pad & cell
        else:
          cell & pad
      line.add span(
        text, (if c <= 31 and c in selectedCols: selectedColour else: white)
      )
    if line.len > 0:
      line[^1].text = line[^1].text.strip(leading = false) # (no trailing blanks)
    result.add line

proc summaryLines*(
    rows: seq[Summary], everyone, verbose: bool, zone: Timezone
): seq[Line] =
  ## A table of the climbs, each the standard way, then how the user did on it:
  ##
  ##     climb                 cat  length   gain  gradient             best    best selected  rank  attempts
  ##     Cerro San Luis (4/5)  4     0.5km   +89m     17.8%  8:25 2019-03-02  9:41 2020-08-14     3         4
  ##
  ## the best time of all the user's attempts, with its date, and (in the selection's colour) the best of those on the
  ## selected rides, with its date, and where that one ranks among all the user's own attempts, then how many there are.  Or, with `everyone`, the people: how many have ridden it, the fastest and who,
  ## and where the user's best is among them.  With `verbose` the attempts (or the people's best times) follow each
  ## climb, the fastest first.
  var cells =
    if everyone:
      @[
        @[
          "climb", "cat", "length", "gain", "gradient", "riders", "fastest", "by", "you"
        ]
      ]
    else:
      @[
        @[
          "climb", "cat", "length", "gain", "gradient", "best", "best selected", "rank",
          "attempts",
        ]
      ]
  for s in rows:
    var tail: seq[string]
    if everyone:
      if s.riders.len == 0:
        tail = @["0", notRecorded, notRecorded, notRecorded]
      else:
        var you = notRecorded
        for r in s.riders:
          if r.me:
            you = rankText(r.rank, r.total)
        tail = @[$s.riders.len, duration(s.riders[0].elapsed), s.riders[0].user, you]
    else:
      if s.attempts.len == 0:
        tail = @[notRecorded, notRecorded, notRecorded, "0"]
      else:
        let fastest = s.best.get
        let chosen = s.best(selectedOnly = true)
        tail = @[
          duration(fastest.elapsed) & " " &
            dateText(int64(fastest.activity.startT), zone),
          (
            if chosen.isSome:
            duration(chosen.get.elapsed) & " " &
              dateText(int64(chosen.get.activity.startT), zone)
            else: notRecorded
          ),
          (if chosen.isSome: $chosen.get.rank else: notRecorded),
          $s.attempts.len,
        ]
    cells.add climbCells(s.climb) & tail
  var right: set[0 .. 31] = {2, 3, 4, 5, 6}
  if not everyone:
    right = right + {7, 8}
  var selectedCols: set[0 .. 31] = {}
  if not everyone:
    selectedCols = {6, 7}
  let table = alignedLines(cells, right, selectedCols)
  result.add table[0]
  for i, s in rows:
    result.add table[i + 1]
    if not verbose:
      continue
    var inner: seq[seq[string]]
    var chosen: seq[bool] # the attempts of selected rides: in the selection's colour
    if everyone:
      for r in s.riders:
        inner.add @[
          $r.rank,
          duration(r.elapsed),
          r.user & (if r.me: " (you)" else: ""),
          dateText(r.startT, zone),
        ]
        chosen.add false
    else:
      var sorted = s.attempts
      sorted.sort(
        proc(a, b: Attempt): int =
          cmp(a.elapsed, b.elapsed)
      )
      for a in sorted:
        inner.add @[$a.rank, duration(a.elapsed), activityLine(a.activity, zone)]
        chosen.add a.selected
    let aligned = columns(inner, {0, 1})
    for j, l in aligned:
      result.add @[span("    " & l, (if chosen[j]: selectedColour else: white))]
