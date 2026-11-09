## A made-up GeoNames world for tests of the names: lines of a country file, the outlines and the list of
## countries, and a network that serves them.

import std/[options, os, strutils]
import nimchoo/db/store
import nimchoo/packages/download/fetch
import nimchoo/packages/download/sources
import nimchoo/modules
import ./[shapefile, zips]

proc gn*(id: int, name: string, lat, lon: float, cls, code: string, pop = 0): string =
  ## A line of a GeoNames file: 19 columns.
  var c = newSeq[string](19)
  c[0] = $id
  c[1] = name
  c[2] = name
  c[4] = $lat
  c[5] = $lon
  c[6] = cls
  c[7] = code
  c[8] = "CL"
  c[14] = $pop
  c.join("\t")

let santiago* = gn(3871336, "Santiago", -33.45694, -70.64827, "P", "PPLC", 4837295)
let sanCristobal* = gn(3871427, "Cerro San Cristóbal", -33.42, -70.63, "T", "HLL")
let pass* = gn(3882052, "Paso Los Libertadores", -32.83, -70.12, "T", "PASS")
let lake* = gn(1, "Laguna del Inca", -32.83, -70.1, "H", "LK")
let road* = gn(2, "Ruta 60", -32.8, -70.2, "R", "RD")
let spring* = gn(3, "Vertiente Fria", -38.37, -73.9, "H", "SPNG")
let barrio* = gn(4, "Lo Barnechea", -33.35, -70.52, "P", "PPLX", 0)

let chileShape* = CountryShape(
  iso: "CL", isoEh: "CL", name: "Chile", rects: @[(-76.0, -56.0, -69.5, -17.0)]
) ## (a rectangle: the whole of Chile for the tests of the names)

proc infoLine*(iso, name: string, id: int): string =
  var cols = newSeq[string](19)
  cols[0] = iso
  cols[4] = name
  cols[16] = $id
  cols.join("\t")

type Net* = ref object
  gets*: seq[string]
  chile*: string

proc envOf*(net: Net): Env =
  result.fetcher.head = proc(url: string): Option[int64] {.closure, raises: [].} =
    none(int64)
  result.fetcher.get = proc(url: string): FetchResult {.closure, raises: [].} =
    net.gets.add url
    try:
      if url == urlFor(naturalEarthCountries):
        return FetchResult(ok: true, status: 200, body: naturalEarthZip([chileShape]))
      if url == urlFor(geonamesCountryInfo):
        return FetchResult(
          ok: true,
          status: 200,
          body:
            infoLine("CL", "Chile", 3895114) & "\n" &
            infoLine("AR", "Argentina", 3865483) & "\n",
        )
      if url == urlFor(geonamesCountry, "CL"):
        return
          FetchResult(ok: true, status: 200, body: makeZip([("CL.txt", net.chile)]))
    except CatchableError:
      return FetchResult(ok: false, message: "cannot make the zip")
    FetchResult(ok: false, status: 404, message: "the server said 404")
  result.freeBytes = proc(dir: string): Option[int64] {.closure, raises: [].} =
    none(int64)

proc fresh*(name: string): tuple[st: Store, dir: string] =
  let top = getTempDir() / "nch-test-features" / name
  removeDir(top)
  (openStore(top / "x.db", allFragments), top / "data")
