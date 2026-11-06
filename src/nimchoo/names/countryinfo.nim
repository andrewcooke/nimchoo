## Reading the list of countries GeoNames publishes (`countryInfo.txt`): ISO code, name and GeoNames id.  Pure.  (The
## outlines are Natural Earth's, read by SpatiaLite: see countries.nim.)

import std/strutils

{.push raises: [].}

type
  CountryInfo* = object
    iso*, name*: string
    geonameId*: int64

func parseCountryInfo*(text: string): seq[CountryInfo] =
  ## The countries: ISO code (column 1), name (5) and GeoNames id (17) of each line that is not a comment.
  for line in text.splitLines:
    if line.len == 0 or line[0] == '#': continue
    let c = line.split('\t')
    if c.len < 17: continue
    try:
      result.add CountryInfo(iso: c[0], name: c[4], geonameId: parseBiggestInt(c[16]))
    except ValueError:
      discard
