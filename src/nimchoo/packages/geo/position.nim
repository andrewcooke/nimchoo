## A position as the user writes it: `LAT,LON` in degrees, latitude first (the order of every position the program takes or
## shows: `--near`, `--at`).  One reader for every command, and a type with named fields, so that the order of latitude and
## longitude cannot be mixed up after it is read.  Pure.

import std/[options, strutils]

{.push raises: [].}

type Position* = tuple[lon, lat: float] ## in degrees

func parsePosition*(s: string): Option[Position] =
  ## "38.72,-9.14": latitude, then longitude, each in range (spaces around them do not matter); none otherwise.
  let parts = s.split(',')
  if parts.len != 2:
    return none(Position)
  try:
    let lat = parseFloat(parts[0].strip)
    let lon = parseFloat(parts[1].strip)
    if lat < -90.0 or lat > 90.0 or lon < -180.0 or lon > 180.0:
      return none(Position)
    some((lon: lon, lat: lat))
  except ValueError:
    none(Position)
