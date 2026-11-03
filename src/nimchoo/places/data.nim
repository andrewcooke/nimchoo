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

{.push raises: [].}

type PlaceRow* = object
  name*, country*: string
  lat*, lon*: float
  population*: int

when defined(nchSmallPlaces):
  const carried = staticRead("cities-test.tsv")
  const isGzipped = false
else:
  const carried = staticRead("cities.tsv.gz")
  const isGzipped = true

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

proc carriedPlaces*(): seq[PlaceRow] =
  ## The list this program carries.
  parsePlaces(unpack(carried, isGzipped))
