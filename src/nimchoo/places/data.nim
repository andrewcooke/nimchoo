## The list of places the program carries, and how to read it.  Built from GeoNames'
## cities5000 (towns and cities of 5,000 people or more: about 70,000 places) by
## tools/makecities.nim, as tab-separated lines `name country lat lon population`, gzipped.
##
## Places data: GeoNames (https://www.geonames.org), licensed CC BY 4.0 (see NOTICE).
##
## Test programs are built with -d:nchSmallPlaces, which carries a short list instead (so
## that making a database for a test takes no time).

import std/[options, strutils]
import zippy
import ../bundle/unpack

{.push raises: [].}

type PlaceRow* = object
  name*, country*: string
  lat*, lon*: float
  population*: int

when defined(nchSmallPlaces):
  const carried = staticRead("cities-test.tsv")
  const listName = "cities-test.tsv"
  const dataVersion* = "test-list"
else:
  const carried = staticRead("cities.tsv.gz")
  const listName = "cities.tsv.gz"
  const dataVersion* = staticRead("cities.version").strip
    ## the SHA-256 of cities.tsv.gz, written by tools/makecities.nim

func parsePlace*(line: string): Option[PlaceRow] =
  ## One line `name TAB country TAB lat TAB lon TAB population`; none if it is not one.
  let f = line.split('\t')
  if f.len != 5 or f[0].len == 0 or f[1].len != 2: return none(PlaceRow)
  try:
    let lat = parseFloat(f[2])
    let lon = parseFloat(f[3])
    if lat < -90 or lat > 90 or lon < -180 or lon > 180: return none(PlaceRow)
    some(PlaceRow(name: f[0], country: f[1], lat: lat, lon: lon, population: parseInt(f[4])))
  except ValueError:
    none(PlaceRow)

func parsePlaces*(text: string): seq[PlaceRow] =
  ## All the places in a text, one to a line (lines that are not places are left out).
  for line in text.splitLines:
    let p = parsePlace(line)
    if p.isSome: result.add p.get

proc unpack*(data: string, gzipped: bool): string =
  ## The text of a list: unzipped if it is gzipped.  Empty if it cannot be read.
  if not gzipped: return data
  try: uncompress(data, dfGzip)
  except ZippyError: ""

const placesBundle* = Bundle(name: listName, data: carried)

func listText*(data: string): string =
  ## The text of a list that is gzipped (as the one the program carries) or plain (as the author
  ## may have written one): told apart by the gzip signature.  Empty if it cannot be read.
  if data.len > 2 and data[0] == '\x1f' and data[1] == '\x8b': unpack(data, true) else: data

proc placesList*(): tuple[rows: seq[PlaceRow], path: string] =
  ## The list to use: the one in the cache's `system/` part (the program's, unpacked, or the
  ## author's); `path` is the author's file, or "" for the program's own.
  let r = resolve(placesBundle)
  (parsePlaces(listText(r.data)), if r.source == soCustom: r.path else: "")

proc placesVersion*(): string =
  ## Which list is in use: the SHA-256 of its file (the same as `dataVersion` for the program's own).
  ## A database remembers which list it was made from, and replaces its places when this changes.
  resolve(placesBundle).hash

proc carriedPlaces*(): seq[PlaceRow] =
  ## The list to use (see `placesList`).
  placesList().rows
