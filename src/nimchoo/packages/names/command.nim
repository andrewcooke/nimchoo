## `nch landmarks`: places of your own, named, that come before every other name (a ride that turns round inside a
## landmark's circle is "<landmark> and back", a climb that tops out in it is called by it).  Suggestions: find
## features of GeoNames by part of their name or by nearness to a position, and pick one to make a landmark of.

import std/[options, strutils]
import ../geo/position
import ../../core/ruled
import ../../core/globals
import ../ui/units
import ../db/store
import ../../core/errors
import ./lookup
import ./open
import ../../core/logfile
import ../confirm/confirm
import ../ui/live
import ../util/args/[args, usage]
import ./params
import ./places
import ./landmarks
import ./suggest

{.push raises: [].}

const commandName* = "landmarks" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch landmarks`, described (for tab completion).
  landmarkSpec().docs

const
  synopsis = """usage: nch landmarks
       nch landmarks --search TEXT
       nch landmarks --near LAT,LON|PLACE
       nch landmarks --add NAME --search TEXT --pick N [--size DISTANCE]
       nch landmarks --add NAME --near LAT,LON|PLACE --pick N [--size DISTANCE]
       nch landmarks --add NAME --at LAT,LON|PLACE [--size DISTANCE]
       nch landmarks --delete NAME -f"""
  intro = @[
    ~"Your own names for places.  Where something is named (a climb, a ride that turns round), a landmark whose circle holds the place comes before every name GeoNames has.  Without options, list the landmarks."
  ]
  notes = @[
    ~"Landmarks are shared by all users (as the climbs are), so `--user` goes nowhere here."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  usageOf(synopsis, width, intro, landmarkSpec().docs, notes)

func suggestionLines(rows: seq[Suggestion], withDistance: bool, width: int): seq[Line] =
  ## The places found, numbered, as a table (`core/ruled.nim`); how far each is, when near a point.
  var header = @["", "name", "kind", "position"]
  if withDistance:
    header.add "from"
  var cells: seq[seq[string]]
  for i, s in rows:
    cells.add @[
      $(i + 1), s.name, s.cls & " " & s.code, positionText((lon: s.lon, lat: s.lat))
    ]
    if withDistance:
      cells[^1].add km(s.distanceM)
  ruled(header, cells, width, right = {0, 4})

func landmarkLines(rows: seq[Landmark], width: int): seq[Line] =
  ## The landmarks as a table (`core/ruled.nim`).
  var cells: seq[seq[string]]
  for l in rows:
    cells.add @[l.name, positionText((lon: l.lon, lat: l.lat)), km(l.radiusM)]
  ruled(@["landmark", "position", "radius"], cells, width, right = {2})

proc resolved(
    st: Store, spot: Spot
): tuple[pos: Position, said: string] {.raises: [StoreError].} =
  ## A position as given: itself, or the place of that name (a landmark, else the biggest of that name among the names loaded:
  ## `places.placeNamed`), with a note of which, in brackets, to say.
  case spot.kind
  of nkPoint:
    (pos: (lon: spot.lon, lat: spot.lat), said: "")
  of nkPlace:
    let p = placeNamed(st, spot.place)
    (pos: (lon: p.lon, lat: p.lat), said: " (" & p.said & ")")
  of nkNone, nkLatest, nkPrevious:
    raiseAssert "landmarks read a position or a place's name only"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch landmarks ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch landmarks", usageText(helpWidth(stderr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch landmarks", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  if g.user.len > 0:
    return usageError(
      g,
      "nch landmarks",
      usageText(helpWidth(stderr)),
      ~"the landmarks are shared by all users: `--user` has no part in this command",
    )
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure(g, "nch landmarks", e.msg)
  try:
    case p.action
    of laDelete:
      let d = p.deleted
      if not d.force:
        g.show(osErr, ~"would delete the landmark {d.name}: add `-f` to do it")
        return exitFailure
      if not removeLandmark(st, d.name):
        return failure(g, "nch landmarks", ~"there is no landmark called '{d.name}'")
      let said = "deleted the landmark " & d.name
      g.log.log(lvInfo, commandName, leDeleted, said)
      sayDeleted(g, plain(said))
      return exitOk
    of laAddAt:
      let a = p.placed
      let at = resolved(st, a.at)
      addLandmark(st, a.name, at.pos.lon, at.pos.lat, a.radiusM)
      let said =
        "made the landmark " & a.name.strip & " at " & positionText(at.pos) & at.said
      g.log.log(lvInfo, commandName, leSaved, said)
      g.show(osOut, plain(said))
      return exitOk
    of laSearch, laNear, laAddPicked:
      let suggest = if p.action == laAddPicked: p.picked.suggestions else: p.suggest
      var found: seq[Suggestion]
      case suggest.kind
      of skSearch:
        found = searchByName(st, suggest.text)
      of skNear:
        # the names round the position are read (and fetched) first
        let near = resolved(st, suggest.near)
        if near.said.len > 0:
          g.show(osErr, plain(near.said.strip(chars = {' ', '(', ')'})))
        let names = openNames(
          g,
          st,
          commandName,
          proc(line: Line) {.closure, raises: [].} =
            g.show(osErr, line),
        )
        if names.isSome:
          try:
            discard names.get.prepare([near.pos.lon], [near.pos.lat], 2000.0)
          except OfflineError:
            g.show(
              osErr,
              ~"`--offline`: only the names already loaded for that area are suggested",
            )
        found = featuresAround(st, near.pos.lon, near.pos.lat)
      if p.action == laAddPicked:
        let a = p.picked
        if a.pick > found.len:
          return failure(
            g, "nch landmarks", ~"there is no suggestion {a.pick} ({found.len} found)"
          )
        let s = found[a.pick - 1]
        addLandmark(st, a.name, s.lon, s.lat, a.radiusM)
        let said =
          "made the landmark " & a.name.strip & " at " & s.name & " (" &
          positionText((lon: s.lon, lat: s.lat)) & ")"
        g.log.log(lvInfo, commandName, leSaved, said)
        g.show(osOut, plain(said))
        return exitOk
      if found.len == 0:
        g.show(
          osOut,
          (
            if suggest.kind == skSearch:
              ~"nothing is called like that among the names loaded (the places you have ridden)"
            else:
              ~"no features within 2 km"
          ),
        )
        return exitOk
      g.showAll(
        osOut, suggestionLines(found, suggest.kind == skNear, helpWidth(stdout))
      )
      return exitOk
    of laList:
      let rows = listLandmarks(st)
      if rows.len == 0:
        g.show(
          osOut,
          ~"no landmarks: `nch landmarks --search TEXT` suggests places to make one of",
        )
      else:
        g.showAll(osOut, landmarkLines(rows, helpWidth(stdout)))
      return exitOk
  except StoreError, DownloadError:
    failure(g, "nch landmarks", getCurrentExceptionMsg())
