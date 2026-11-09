## `nch landmarks`: places of your own, named, that come before every other name (a ride that turns round inside a
## landmark's circle is "<landmark> and back", a climb that tops out in it is called by it).  Suggestions: find
## features of GeoNames by part of their name or by nearness to a position, and pick one to make a landmark of.

import std/[options, strutils]
import ../cli/catalog
import ../core/globals
import ../climbs/report
import ../packages/ui/units
import ../db/store
import ../core/errors
import ../names/[lookup, open]
import ../core/logfile
import ../user/wipe
import ./[landmarks, params, suggest]

{.push raises: [].}

const usage* = """usage: nch landmarks
       nch landmarks --search TEXT
       nch landmarks --near LON,LAT
       nch landmarks --add NAME --search TEXT --pick N [--radius METRES]
       nch landmarks --add NAME --near LON,LAT --pick N [--radius METRES]
       nch landmarks --add NAME --at LON,LAT [--radius METRES]
       nch landmarks --delete NAME -f

Your own names for places.  Where something is named (a climb, a ride that turns round), a landmark whose circle holds
the place comes before every name GeoNames has.  Without options, list the landmarks.

  --search TEXT   suggest features of GeoNames whose name holds TEXT (any kind: streams, farms, parks ...), numbered;
                  only places whose cells have been read can be found (the places you have ridden)
  --near LON,LAT  suggest the features within 2 km of a position, nearest first, numbered (the names for that area are
                  fetched if need be)
  --add NAME      make a landmark called NAME, at the position of suggestion N (`--pick N`, from the same --search or
                  --near) or at a position you give (`--at LON,LAT`); its circle has the radius of --radius
                  (100 to 20,000 metres; default 1,000)
  --delete NAME   delete the landmark (needs -f)
  -f, --force     really do it
  -h, --help      show this help

Landmarks are shared by all users (as the climbs are), so `--user` goes nowhere here.
"""

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
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch landmarks", usage, p.problem)
  if g.user.len > 0:
    return usageError(
      "nch landmarks", usage,
      "the landmarks are shared by all users: --user has no part in this command",
    )
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch landmarks", e.msg)
  try:
    if p.delete and not p.force:
      stderr.say "would delete the landmark " & p.name & ": add -f to do it\n"
      return exitFailure
    if p.delete:
      if not removeLandmark(st, p.name):
        return failure("nch landmarks", "there is no landmark called '" & p.name & "'")
      let said = "deleted the landmark " & p.name
      g.log.log(lvInfo, $cmLandmarks, leDeleted, said)
      sayDeleted(said)
      return exitOk
    if p.add and p.at.isSome:
      addLandmark(st, p.name, p.at.get.lon, p.at.get.lat, p.radiusM)
      let said =
        "made the landmark " & p.name.strip & " at " &
        positionText(p.at.get.lon, p.at.get.lat)
      g.log.log(lvInfo, $cmLandmarks, leSaved, said)
      stdout.say said & "\n"
      return exitOk
    if p.search.len > 0 or p.near.isSome:
      var found: seq[Suggestion]
      if p.search.len > 0:
        found = searchByName(st, p.search)
      else:
        # the names round the position are read (and fetched) first
        let names = openNames(
          g,
          st,
          cmLandmarks,
          proc(line: string) {.closure, raises: [].} =
            stderr.say line & "\n"
          ,
        )
        if names.isSome:
          discard names.get.prepare([p.near.get.lon], [p.near.get.lat], 2000.0)
        found = featuresAround(st, p.near.get.lon, p.near.get.lat)
      if p.add:
        if p.pick > found.len:
          return failure(
            "nch landmarks",
            "there is no suggestion " & $p.pick & " (" & $found.len & " found)",
          )
        let s = found[p.pick - 1]
        addLandmark(st, p.name, s.lon, s.lat, p.radiusM)
        let said =
          "made the landmark " & p.name.strip & " at " & s.name & " (" &
          positionText(s.lon, s.lat) & ")"
        g.log.log(lvInfo, $cmLandmarks, leSaved, said)
        stdout.say said & "\n"
        return exitOk
      if found.len == 0:
        stdout.say (
          if p.search.len > 0:
          "nothing is called like that among the names loaded (the places you have ridden)\n"
          else: "no features within 2 km\n"
        )
        return exitOk
      for l in suggestionLines(found, p.near.isSome):
        stdout.say l & "\n"
      return exitOk
    let rows = listLandmarks(st)
    if rows.len == 0:
      stdout.say "no landmarks: `nch landmarks --search TEXT` suggests places to make one of\n"
    else:
      for l in landmarkLines(rows):
        stdout.say l & "\n"
    exitOk
  except StoreError, DownloadError:
    failure("nch landmarks", getCurrentExceptionMsg())
