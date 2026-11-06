## What `nch climbs` shows of the rides over each climb: a summary line a climb, and with -v the attempts under it.
## There are two ranks, and they are never shown together.  The personal rank compares one attempt with the user's own
## attempts on the climb ("3 of 12"); the leaderboard rank compares each person's best time ("4 of 6", with `--everyone`).
## Both are worked out when they are wanted, from the efforts; nothing is stored.
##
## Which climbs are shown is not decided here: the selected rides' climbs, or those whose name holds some text.
## Whatever the climbs, all their attempts count, those of the selected rides and the others.

import std/[algorithm, options, sequtils, strutils, tables, times]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ../fit/time
import ../importer/describe
import ../selection/fold
import std/unicode
import ../ui/[palette, style, units]
import ./[describe, display, report]

{.push raises: [].}

type
  Attempt* = object
    ## One pass of the user over a climb.
    activity*: ActivityInfo
    elapsed*: float                ## seconds, gate to gate
    rank*, total*: int             ## the personal rank: 1 for the fastest of the user's own attempts
    selected*: bool                ## the ride is one of the selected activities

  Rider* = object
    ## A person's best time on a climb.
    user*: string
    elapsed*: float
    startT*: int64                 ## when the ride began (Unix seconds)
    rank*, total*: int             ## the leaderboard rank: 1 for the fastest person
    me*: bool

  Summary* = object
    climb*: ClimbInfo
    attempts*: seq[Attempt]        ## the user's, oldest first
    riders*: seq[Rider]            ## each person's best, the fastest first

func rankOf*(times: openArray[float], t: float): int =
  ## 1 plus the number of times that are shorter: equal times share a rank.
  result = 1
  for x in times:
    if x < t: inc result

# --- which climbs

proc selectedClimbs*(st: Store): seq[int64] {.raises: [StoreError].} =
  ## The climbs (not retired) that the selected activities went up, the biggest first.
  guard:
    for r in st.db.fastRows(sql"""
        select s.id from sector s
         where s.retired = 0 and exists (select 1 from effort e where e.sector_id = s.id
               and e.activity_id in (select activity_id from selection where user_id = ?))
         order by s.gain_m desc, s.id""", st.userId):
      try: result.add parseBiggestInt(r[0])
      except ValueError: raiseStore("a bad id")

proc namedClimbs*(st: Store, texts: seq[string]): seq[int64] {.raises: [StoreError].} =
  ## The climbs (not retired) whose name as shown ("Farellones (2/3)") holds any of the texts, case and accents ignored,
  ## the biggest first.
  let names = shownNames(st)
  let wanted = texts.mapIt(foldText(it))
  guard:
    for r in st.db.fastRows(sql"select id from sector where retired = 0 order by gain_m desc, id"):
      try:
        let id = parseBiggestInt(r[0])
        let shown = foldText(names.getOrDefault(id, ""))
        for w in wanted:
          if w in shown:
            result.add id
            break
      except ValueError: raiseStore("a bad id")

# --- the rows

func num(s: string): float {.raises: [ValueError].} = parseFloat(s)

proc summaries*(st: Store, ids: seq[int64]): seq[Summary] {.raises: [StoreError].} =
  ## The climbs `ids`, in that order, with the user's attempts and everyone's best times.
  let names = shownNames(st)
  guard:
    for id in ids:
      var sum = Summary()
      try:
        for r in st.db.fastRows(sql"select length_m, gain_m, gradient, coalesce(category, '') from sector where id = ?", id):
          sum.climb = climbOf(names.getOrDefault(id, unnamed), r[3], num(r[0]), num(r[1]), num(r[2]))
        var times: seq[float]
        for r in st.db.fastRows(sql"""
            select a.start_t, coalesce(a.sport, ''), coalesce(a.sub_sport, ''), a.distance_m, a.timer_s,
                   coalesce(a.start_place, ''), coalesce(a.name, ''), e.elapsed_s,
                   a.id in (select activity_id from selection where user_id = ?)
              from effort e join activity a on a.id = e.activity_id join file f on f.id = a.file_id
             where e.sector_id = ? and f.user_id = ? order by a.start_t, e.start_t""", st.userId, id, st.userId):
          let info = ActivityInfo(startT: UnixTime(parseBiggestInt(r[0])), sport: r[1], subSport: r[2],
                                  distanceM: (if r[3].len > 0: some(num(r[3])) else: none(float)),
                                  activeS: (if r[4].len > 0: some(num(r[4])) else: none(float)), place: r[5], name: r[6])
          sum.attempts.add Attempt(activity: info, elapsed: num(r[7]), selected: r[8] == "1")
          times.add num(r[7])
        for a in sum.attempts.mitems:
          a.rank = rankOf(times, a.elapsed)
          a.total = times.len
        # each person's best
        var best = initTable[string, Rider]()
        for r in st.db.fastRows(sql"""
            select f.user_id, u.name, e.elapsed_s, a.start_t
              from effort e join activity a on a.id = e.activity_id join file f on f.id = a.file_id
              join user u on u.id = f.user_id
             where e.sector_id = ?""", id):
          let t = num(r[2])
          if r[0] notin best or t < best[r[0]].elapsed:
            best[r[0]] = Rider(user: r[1], elapsed: t, startT: parseBiggestInt(r[3]), me: r[0] == $int64(st.userId))
        for rider in best.values: sum.riders.add rider
        sum.riders.sort(proc(a, b: Rider): int = cmp(a.elapsed, b.elapsed))
        let bests = sum.riders.mapIt(it.elapsed)
        for rider in sum.riders.mitems:
          rider.rank = rankOf(bests, rider.elapsed)
          rider.total = sum.riders.len
      except ValueError:
        raiseStore("a bad number in the climbs")
      result.add sum

# --- the lines

func rankText(rank, total: int): string = $rank & " of " & $total

proc dateText(startT: int64, zone: Timezone): string =
  dateTimeText(UnixTime(startT), zone)[0 .. 9]

func best(s: Summary, selectedOnly = false): Option[Attempt] =
  ## The user's fastest attempt (the first, if several are equal); with `selectedOnly`, the fastest of those on selected rides.
  for a in s.attempts:
    if selectedOnly and not a.selected: continue
    if result.isNone or a.elapsed < result.get.elapsed: result = some(a)

func alignedLines(cells: seq[seq[string]], right, selectedCols: set[0 .. 31]): seq[Line] =
  ## The rows with their cells lined up (two spaces between), those in `right` to the right, and those in `selectedCols`
  ## in the selection's colour.
  var widths: seq[int]
  for row in cells:
    for c, cell in row:
      if c >= widths.len: widths.add 0
      widths[c] = max(widths[c], cell.runeLen)
  for row in cells:
    var line: Line
    for c, cell in row:
      if c > 0: line.add span("  ")
      let pad = repeat(' ', widths[c] - cell.runeLen)
      let text = if c <= 31 and c in right: pad & cell else: cell & pad
      line.add span(text, (if c <= 31 and c in selectedCols: blue else: white))
    if line.len > 0:
      line[^1].text = line[^1].text.strip(leading = false)         # (no trailing blanks)
    result.add line

proc summaryLines*(rows: seq[Summary], everyone, verbose: bool, zone: Timezone): seq[Line] =
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
    if everyone: @[@["climb", "cat", "length", "gain", "gradient", "riders", "fastest", "by", "you"]]
    else: @[@["climb", "cat", "length", "gain", "gradient", "best", "best selected", "rank", "attempts"]]
  for s in rows:
    var tail: seq[string]
    if everyone:
      if s.riders.len == 0: tail = @["0", notRecorded, notRecorded, notRecorded]
      else:
        var you = notRecorded
        for r in s.riders:
          if r.me: you = rankText(r.rank, r.total)
        tail = @[$s.riders.len, duration(s.riders[0].elapsed), s.riders[0].user, you]
    else:
      if s.attempts.len == 0: tail = @[notRecorded, notRecorded, notRecorded, "0"]
      else:
        let fastest = s.best.get
        let chosen = s.best(selectedOnly = true)
        tail = @[duration(fastest.elapsed) & " " & dateText(int64(fastest.activity.startT), zone),
                 (if chosen.isSome: duration(chosen.get.elapsed) & " " & dateText(int64(chosen.get.activity.startT), zone) else: notRecorded),
                 (if chosen.isSome: $chosen.get.rank else: notRecorded),
                 $s.attempts.len]
    cells.add climbCells(s.climb) & tail
  var right: set[0 .. 31] = {2, 3, 4, 5, 6}
  if not everyone: right = right + {7, 8}
  var selectedCols: set[0 .. 31] = {}
  if not everyone: selectedCols = {6, 7}
  let table = alignedLines(cells, right, selectedCols)
  result.add table[0]
  for i, s in rows:
    result.add table[i + 1]
    if not verbose: continue
    var inner: seq[seq[string]]
    var chosen: seq[bool]                  # the attempts of selected rides: in the selection's colour
    if everyone:
      for r in s.riders:
        inner.add @[rankText(r.rank, r.total), duration(r.elapsed), r.user & (if r.me: " (you)" else: ""), dateText(r.startT, zone)]
        chosen.add false
    else:
      var sorted = s.attempts
      sorted.sort(proc(a, b: Attempt): int = cmp(a.elapsed, b.elapsed))
      for a in sorted:
        inner.add @[rankText(a.rank, a.total), duration(a.elapsed), activityLine(a.activity, zone)]
        chosen.add a.selected
    let aligned = columns(inner, {0, 1})
    for j, l in aligned:
      result.add @[span("    " & l, (if chosen[j]: blue else: white))]
