## Everything nch downloads, listed in one place: where from, what the file is, how big it may be.
## (Data that must travel with the program, or be pinned, is not downloaded: see TODO.md, task 13.)
## A pattern's `{arg}` is replaced by the argument given when the source is fetched (a country code).

{.push raises: [].}

type Source* = object
  name*: string            ## also the directory of its files under `data/` in the cache
  url*: string             ## the address, with `{arg}` where the argument goes
  file*: string            ## the name of the file kept
  zipEntry*: string        ## the entry the zip must hold ("" if the file is not a zip)
  maxBytes*: int64         ## a bigger file is refused (before it is fetched, if the server says)
  attribution*: string     ## the licence and who to credit (also in NOTICE)
  why*: string             ## what it is needed for, said before it is fetched (`{arg}` as in the others)
  label*: string           ## a few words for the screen ("locations in CL"); `why` is for the log

const
  geonamesCredit* = "GeoNames (https://www.geonames.org), licensed under CC BY 4.0"

  geonamesCountry* = Source(
    name: "geonames", url: "https://download.geonames.org/export/dump/{arg}.zip", file: "{arg}.zip",
    zipEntry: "{arg}.txt", maxBytes: 200 * 1024 * 1024, attribution: geonamesCredit,
    why: "names of places and mountains in {arg} to name climbs and activities", label: "locations in {arg}")
    ## One country's places and features, by its ISO code ("CL"); the United States is the largest, 71 MB.

  geonamesOutlines* = Source(
    name: "geonames", url: "https://download.geonames.org/export/dump/shapes_simplified_low.json.zip",
    file: "shapes_simplified_low.json.zip", zipEntry: "shapes_simplified_low.json",
    maxBytes: 20 * 1024 * 1024, attribution: geonamesCredit,
    why: "country shapes, to infer country from position", label: "country outlines")
    ## The simplified outlines of the countries (1.3 MB), keyed by GeoNames id.

  geonamesCountryInfo* = Source(
    name: "geonames", url: "https://download.geonames.org/export/dump/countryInfo.txt",
    file: "countryInfo.txt", zipEntry: "", maxBytes: 5 * 1024 * 1024, attribution: geonamesCredit,
    why: "the list of countries, for their names and codes", label: "countries")
    ## The countries: ISO code, name, GeoNames id (32 KB).

  allSources* = [geonamesCountry, geonamesOutlines, geonamesCountryInfo]

func fill(pattern, arg: string): string =
  var i = 0
  while i < pattern.len:
    if pattern[i] == '{' and i + 5 < pattern.len + 1 and pattern[i ..< min(pattern.len, i + 5)] == "{arg}":
      result.add arg
      i += 5
    else:
      result.add pattern[i]
      inc i

func urlFor*(s: Source, arg = ""): string = fill(s.url, arg)
func fileFor*(s: Source, arg = ""): string = fill(s.file, arg)
func entryFor*(s: Source, arg = ""): string = fill(s.zipEntry, arg)
func whyFor*(s: Source, arg = ""): string = fill(s.why, arg)
func labelFor*(s: Source, arg = ""): string = fill(s.label, arg)
