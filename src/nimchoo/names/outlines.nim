## Reading the files GeoNames publishes about countries: the list of countries (`countryInfo.txt`) and
## their simplified outlines (`shapes_simplified_low.json`, GeoJSON: each country a polygon or several,
## keyed by its GeoNames id).  Pure.

import std/[json, strutils]

{.push raises: [].}

type
  CountryInfo* = object
    iso*, name*: string
    geonameId*: int64

  Outline* = object
    geonameId*: int64
    wkt*: string                 ## "MULTIPOLYGON(((lon lat, ...), ...))"

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

func degrees(x: float): string = formatFloat(x, ffDecimal, 5)       # (a metre or so)

func ringText(ring: JsonNode): string =
  var points: seq[string]
  for p in ring.getElems:
    let xy = p.getElems
    if xy.len >= 2: points.add degrees(xy[0].getFloat) & " " & degrees(xy[1].getFloat)
  "(" & points.join(", ") & ")"

func polygonText(rings: JsonNode): string =
  var parts: seq[string]
  for ring in rings.getElems: parts.add ringText(ring)
  "(" & parts.join(", ") & ")"

proc parseOutlines*(text: string): seq[Outline] {.raises: [ValueError].} =
  ## The outline of each country in the GeoJSON, as well-known text.  A ValueError if it is not that.
  var doc: JsonNode
  try:
    doc = parseJson(text)
  except CatchableError:
    raise newException(ValueError, "not JSON: " & getCurrentExceptionMsg())
  let features = doc{"features"}
  if features.isNil or features.kind != JArray:
    raise newException(ValueError, "no features in the outlines")
  for f in features.getElems:
    let id = f{"properties", "geoNameId"}
    let g = f{"geometry"}
    if id.isNil or g.isNil: continue
    var polygons: seq[string]
    case g{"type"}.getStr
    of "Polygon": polygons.add polygonText(g{"coordinates"})
    of "MultiPolygon":
      for poly in g{"coordinates"}.getElems: polygons.add polygonText(poly)
    else: continue
    if polygons.len == 0: continue
    try:
      result.add Outline(geonameId: parseBiggestInt(id.getStr), wkt: "MULTIPOLYGON(" & polygons.join(", ") & ")")
    except ValueError:
      continue

# --- a point in an outline

type
  Ring* = seq[tuple[x, y: float]]
  Shape* = seq[seq[Ring]]          ## polygons; each is its rings, the outer one first and then the holes

func parseShape*(wkt: string): Shape =
  ## The polygons of "MULTIPOLYGON(((lon lat, ...), (hole)), ((...)))".  Whatever is not that gives nothing.
  var depth = 0
  var ringStart = 0
  for i, c in wkt:
    case c
    of '(':
      inc depth
      if depth == 2: result.add @[]
      elif depth == 3: ringStart = i + 1
    of ')':
      if depth == 3 and result.len > 0:
        var ring: Ring
        for pair in wkt[ringStart ..< i].split(','):
          let xy = pair.splitWhitespace
          if xy.len >= 2:
            try: ring.add (parseFloat(xy[0]), parseFloat(xy[1]))
            except ValueError: discard
        result[^1].add ring
      dec depth
    else: discard

func inRing(ring: Ring, x, y: float): bool =
  ## The even-odd rule: a ray to the east crosses the ring an odd number of times if the point is inside.
  var j = ring.len - 1
  for i in 0 ..< ring.len:
    let (xi, yi) = ring[i]
    let (xj, yj) = ring[j]
    if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
      result = not result
    j = i

func contains*(shape: Shape, x, y: float): bool =
  ## Whether the point is inside one of the polygons (holes are outside).  Tolerant of outlines that a
  ## strict geometry library calls invalid: it only counts crossings.
  for polygon in shape:
    var inside = false
    for ring in polygon:
      if inRing(ring, x, y): inside = not inside
    if inside: return true
