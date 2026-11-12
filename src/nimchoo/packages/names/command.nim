## `nch landmarks`: places of your own, named, that come before every other name (a ride that turns round inside a
## landmark's circle is "<landmark> and back", a climb that tops out in it is called by it).  Suggestions: find
## features of GeoNames by part of their name or by nearness to a position, and pick one to make a landmark of.

import std/[options, strutils]
import ../ui/columns
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
       nch landmarks --near LAT,LON
       nch landmarks --add NAME --search TEXT --pick N [--radius METRES]
       nch landmarks --add NAME --near LAT,LON --pick N [--radius METRES]
       nch landmarks --add NAME --at LAT,LON [--radius METRES]
       nch landmarks --delete NAME -f"""
  intro =
    """Your own names for places.  Where something is named (a climb, a ride that turns round), a landmark whose circle
holds the place comes before every name GeoNames has.  Without options, list the landmarks."""
  notes =
    "Landmarks are shared by all users (as the climbs are), so `--user` goes nowhere here."

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the notes, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(landmarkSpec().docs, width).join("\n") & "\n\n" & prose(notes, width) &
    "\n"

func positionText(lon, lat: float): string =
  formatFloat(lat, ffDecimal, 5) & ", " & formatFloat(lon, ffDecimal, 5)

func suggestionLines(rows: seq[Suggestion], withDistance: bool): seq[string] =
  var cells = @[@["", "name", "kind", "position", (if withDistance: "from" else: "")]]
  for i, s in rows:
    cells.add @[
      $(i + 1),
      s.name,
      s.cls & " " & s.code,
      positionText(s.lon, s.lat),
      (if withDistance: km(s.distanceM) else: ""),
    ]
  columns(cells, {0})

proc landmarkLines(rows: seq[Landmark]): seq[string] =
  var cells = @[@["landmark", "position", "radius"]]
  for l in rows:
    cells.add @[l.name, positionText(l.lon, l.lat), km(l.radiusM)]
  columns(cells, {2})

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch landmarks ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch landmarks", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  if g.user.len > 0:
    return usageError(
      "nch landmarks",
      usageText(helpWidth(stderr)),
      "the landmarks are shared by all users: --user has no part in this command",
    )
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch landmarks", e.msg)
  try:
    case p.action
    of laDelete:
      let d = p.deleted
      if not d.force:
        stderr.say "would delete the landmark " & d.name & ": add -f to do it\n"
        return exitFailure
      if not removeLandmark(st, d.name):
        return failure("nch landmarks", "there is no landmark called '" & d.name & "'")
      let said = "deleted the landmark " & d.name
      g.log.log(lvInfo, commandName, leDeleted, said)
      sayDeleted(said)
      return exitOk
    of laAddAt:
      let a = p.placed
      addLandmark(st, a.name, a.at.lon, a.at.lat, a.radiusM)
      let said =
        "made the landmark " & a.name.strip & " at " & positionText(a.at.lon, a.at.lat)
      g.log.log(lvInfo, commandName, leSaved, said)
      stdout.say said & "\n"
      return exitOk
    of laSearch, laNear, laAddPicked:
      let suggest = if p.action == laAddPicked: p.picked.suggestions else: p.suggest
      var found: seq[Suggestion]
      case suggest.kind
      of skSearch:
        found = searchByName(st, suggest.text)
      of skNear:
        # the names round the position are read (and fetched) first
        let names = openNames(
          g,
          st,
          commandName,
          proc(line: string) {.closure, raises: [].} =
            stderr.say line & "\n"
          ,
        )
        if names.isSome:
          try:
            discard names.get.prepare([suggest.near.lon], [suggest.near.lat], 2000.0)
          except OfflineError:
            stderr.say "--offline: only the names already loaded for that area are suggested\n"
        found = featuresAround(st, suggest.near.lon, suggest.near.lat)
      if p.action == laAddPicked:
        let a = p.picked
        if a.pick > found.len:
          return failure(
            "nch landmarks",
            "there is no suggestion " & $a.pick & " (" & $found.len & " found)",
          )
        let s = found[a.pick - 1]
        addLandmark(st, a.name, s.lon, s.lat, a.radiusM)
        let said =
          "made the landmark " & a.name.strip & " at " & s.name & " (" &
          positionText(s.lon, s.lat) & ")"
        g.log.log(lvInfo, commandName, leSaved, said)
        stdout.say said & "\n"
        return exitOk
      if found.len == 0:
        stdout.say (
          if suggest.kind == skSearch:
          "nothing is called like that among the names loaded (the places you have ridden)\n"
          else: "no features within 2 km\n"
        )
        return exitOk
      for l in suggestionLines(found, suggest.kind == skNear):
        stdout.say l & "\n"
      return exitOk
    of laList:
      let rows = listLandmarks(st)
      if rows.len == 0:
        stdout.say "no landmarks: `nch landmarks --search TEXT` suggests places to make one of\n"
      else:
        for l in landmarkLines(rows):
          stdout.say l & "\n"
      return exitOk
  except StoreError, DownloadError:
    failure("nch landmarks", getCurrentExceptionMsg())
