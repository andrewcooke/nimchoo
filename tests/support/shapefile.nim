## A shapefile made in memory, for tests (the .shp, .shx and .dbf of a few countries, each a set of rectangles), and the
## zip that Natural Earth serves it in.  The format: a 100-byte header, then a record for each shape (big-endian
## numbers for the file layout, little-endian for the shapes); the .shx is an index of the records; the .dbf is a table
## of text fields.  Written for a little-endian machine.

import ./zips

type
  Rect* = tuple[x0, y0, x1, y1: float]

  CountryShape* = object
    iso*, isoEh*, name*: string
      ## ISO_A2, ISO_A2_EH (Natural Earth's main code is -99 for a few) and NAME
    rects*: seq[Rect]

  Shapefile* = object
    shp*, shx*, dbf*: string

func le32(x: int): string =
  for i in 0 .. 3:
    result.add char((x shr (8 * i)) and 0xff)

func be32(x: int): string =
  for i in countdown(3, 0):
    result.add char((x shr (8 * i)) and 0xff)

func lef(x: float): string =
  let bits = cast[uint64](x)
  for i in 0 .. 7:
    result.add char((bits shr (8 * i)) and 0xff)

func padded(s: string, n: int): string =
  result = s
  while result.len < n:
    result.add ' '
  result = result[0 ..< n]

func header(words: int, box: Rect): string =
  result =
    be32(9994) & be32(0) & be32(0) & be32(0) & be32(0) & be32(0) & be32(words) &
    le32(1000) & le32(5) & lef(box.x0) & lef(box.y0) & lef(box.x1) & lef(box.y1) & lef(
      0
    ) & lef(0) & lef(0) & lef(0)

func record(c: CountryShape): string =
  ## The content of a polygon record: each rectangle a clockwise ring of five points.
  var box = c.rects[0]
  for r in c.rects:
    box = (min(box.x0, r.x0), min(box.y0, r.y0), max(box.x1, r.x1), max(box.y1, r.y1))
  result =
    le32(5) & lef(box.x0) & lef(box.y0) & lef(box.x1) & lef(box.y1) & le32(c.rects.len) &
    le32(5 * c.rects.len)
  for i in 0 ..< c.rects.len:
    result.add le32(5 * i)
  for r in c.rects:
    for (x, y) in [(r.x0, r.y0), (r.x0, r.y1), (r.x1, r.y1), (r.x1, r.y0), (r.x0, r.y0)]:
      result.add lef(x) & lef(y)

proc makeShapefile*(countries: openArray[CountryShape]): Shapefile =
  var all = countries[0].rects[0]
  for c in countries:
    for r in c.rects:
      all = (min(all.x0, r.x0), min(all.y0, r.y0), max(all.x1, r.x1), max(all.y1, r.y1))
  var shp, shx: string
  var words = 50 # (the header is 100 bytes)
  for i, c in countries:
    let content = record(c)
    shx.add be32(words) & be32(content.len div 2)
    shp.add be32(i + 1) & be32(content.len div 2) & content
    words += 4 + content.len div 2
  result.shp = header(words, all) & shp
  result.shx = header(50 + 4 * countries.len, all) & shx
  # the table: three text fields
  let fields = [("ISO_A2", 10), ("ISO_A2_EH", 10), ("NAME", 40)]
  let recordLen = 1 + 60
  var dbf =
    "\3" & "\x7e\x0b\x06" & le32(countries.len) &
    $char((32 + 32 * fields.len + 1) and 0xff) & $char((32 + 32 * fields.len + 1) shr 8) &
    $char(recordLen) & $char(0)
  while dbf.len < 32:
    dbf.add '\0'
  for (name, len) in fields:
    var d = name
    while d.len < 11:
      d.add '\0'
    d.add 'C'
    d.add "\0\0\0\0"
    d.add char(len)
    d.add '\0'
    while d.len < 32:
      d.add '\0'
    dbf.add d
  dbf.add '\x0d'
  for c in countries:
    dbf.add ' ' & padded(c.iso, 10) & padded(c.isoEh, 10) & padded(c.name, 40)
  dbf.add '\x1a'
  result.dbf = dbf

proc naturalEarthZip*(countries: openArray[CountryShape]): string =
  ## What Natural Earth serves: a zip of the three files.
  let f = makeShapefile(countries)
  makeZip(
    [
      ("ne_50m_admin_0_countries.shp", f.shp),
      ("ne_50m_admin_0_countries.shx", f.shx),
      ("ne_50m_admin_0_countries.dbf", f.dbf),
    ]
  )
