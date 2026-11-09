import std/[options, os, strutils, unittest]
import db_connector/db_sqlite
import ../support/shims
import nimchoo/db/store
import nimchoo/errors
import nimchoo/download/fetch
import nimchoo/names/[countries, features]
import ../support/[namesdata, zips]

proc box(lon0, lat0, lon1, lat1: float): Box =
  (lon0: lon0, lat0: lat0, lon1: lon1, lat1: lat1)

suite "names: a line of a GeoNames file":
  test "every kind of feature is read, with its class, code and population":
    let f = parseFeature(sanCristobal)
    check f.isSome and f.get.id == 3871427 and f.get.name == "Cerro San Cristóbal"
    check f.get.cls == "T" and f.get.code == "HLL" and abs(f.get.lat + 33.42) < 1e-9 and
      abs(f.get.lon + 70.63) < 1e-9
    let p = parseFeature(santiago)
    check p.isSome and p.get.population == 4837295 and p.get.code == "PPLC"
    check parseFeature(pass).get.code == "PASS"
    check parseFeature(barrio).get.population == 0
    for line in [lake, road, spring]:
      # (water, roads, springs: all kept now; the rules choose)
      check parseFeature(line).isSome
    check parseFeature(lake).get.cls == "H" and parseFeature(road).get.cls == "R"
  test "short and broken lines are left out; so are lines with no name":
    check parseFeature("").isNone
    check parseFeature("1\tName\tName\t\t-33.4\t-70.6\tT").isNone # cut short
    check parseFeature(gn(5, "", -33.0, -70.0, "P", "PPL")).isNone # no name
    check parseFeature(gn(6, "X", -33.0, -70.0, "P", "PPL").replace("-33.0", "north")).isNone

suite "names: cells":
  test "a cell is the whole degrees at its south-west corner: floor, not truncation":
    check cellOf(-70.12, -32.83) == (-71, -33)
    check cellOf(70.12, 32.83) == (70, 32)
    check cellOf(-0.5, -0.5) == (-1, -1)
    check cellOf(0.0, 0.0) == (0, 0)
    check cellOf(-71.0, -33.0) == (-71, -33)
      # a whole degree is the corner of its own cell
    check cellOf(0.5, -0.5) == (0, -1)
  test "the date line: 180 is -180, and longitudes past it wrap":
    check cellOf(180.0, 10.0) == (-180, 10)
    check cellOf(179.5, 10.0) == (179, 10)
    check cellOf(-180.0, 10.0) == (-180, 10)
    check cellOf(-179.5, 10.0) == (-180, 10)
    check cellOf(185.0, 10.0) == (-175, 10)
    check cellOf(-185.0, 10.0) == (175, 10)
  test "the poles: latitude 90 is in the top row, -90 in the bottom":
    check cellOf(0.0, 90.0) == (0, 89)
    check cellOf(0.0, 89.9) == (0, 89)
    check cellOf(0.0, -90.0) == (0, -90)
    check cellOf(0.0, -89.9) == (0, -90)
  test "the cells of a box, negatives and zero included":
    check cellsOf(box(-70.2, -33.1, -69.9, -32.9)).len == 4 # -71 and -70 by -34 and -33
    check (-71, -34) in cellsOf(box(-70.2, -33.1, -69.9, -32.9))
    check (-70, -33) in cellsOf(box(-70.2, -33.1, -69.9, -32.9))
    check cellsOf(box(-0.5, -0.5, 0.5, 0.5)).len == 4
    check cellsOf(box(10.2, 20.2, 10.8, 20.8)) == @[(10, 20)]
  test "a box over the date line takes the cells on both sides, once":
    let cs = cellsOf(box(179.5, 10.2, 180.5, 10.8))
    check cs.len == 2 and (179, 10) in cs and (-180, 10) in cs
  test "a box over a pole stays inside the grid":
    for c in cellsOf(box(-10.0, 89.5, 10.0, 91.0)):
      check c.lat >= -90 and c.lat <= 89
    for c in cellsOf(box(-10.0, -91.0, 10.0, -89.5)):
      check c.lat >= -90 and c.lat <= 89

suite "names: loading cells of a country":
  test "a cell is read once, with every feature in it; the cell is recorded":
    let net = Net(
      chile:
        [santiago, sanCristobal, pass, lake, road, spring, barrio, "garbage line"].join(
          "\n"
        ) & "\n"
    )
    let (st, dir) = fresh("load")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
      # the cell -71, -34 and -71, -34 only
    # Santiago (-70.65, -33.46), the hill (-70.63, -33.42) are in cell (-71, -34); Lo Barnechea (-70.52, -33.35) too
    check st.db.getValue(sql"select count(*) from feature") == "3"
    check st.db.getValue(sql"select count(*) from coverage") == "1"
    check st.db.getValue(
      sql"select features from coverage where country = 'CL' and cell_lon = -71 and cell_lat = -34"
    ) == "3"
    # the pass, the lake and the road are in cell (-71, -33): not read
    check st.db.getValue(
      sql"select count(*) from feature where name = 'Paso Los Libertadores'"
    ) == "0"
    let gets = net.gets.len
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
    check net.gets.len == gets # nothing more fetched
    check st.db.getValue(sql"select count(*) from feature") == "3"
  test "another cell is read from the file already in the cache: no second fetch":
    let net = Net(chile: [santiago, pass, lake, road].join("\n") & "\n")
    let (st, dir) = fresh("second")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
    let gets = net.gets.len
    ensureCells(names, "CL", box(-70.2, -32.9, -70.05, -32.7)) # cell -71, -33
    check net.gets.len == gets
    check st.db.getValue(sql"select count(*) from coverage") == "2"
    check st.db.getValue(sql"select name from feature where code = 'PASS'") ==
      "Paso Los Libertadores"
    check st.db.getValue(sql"select count(*) from feature where name = 'Ruta 60'") == "1"
      # every class is kept
    # the spatial index finds a feature by a box
    check st.db.getValue(
      sql"""select name from feature where id in (select ROWID from SpatialIndex
        where f_table_name = 'feature' and f_geometry_column = 'geom' and
              search_frame = BuildMbr(-70.13, -32.84, -70.11, -32.82))"""
    ) == "Paso Los Libertadores"
  test "a cell with nothing in it is recorded too, so it is not read again":
    let net = Net(chile: santiago & "\n")
    let (st, dir) = fresh("empty")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    ensureCells(names, "CL", box(-60.5, -40.5, -60.2, -40.2))
    check st.db.getValue(sql"select features from coverage") == "0"
    check st.db.getValue(sql"select count(*) from feature") == "0"
  test "loading again after the table was emptied does not double anything":
    let net = Net(chile: santiago & "\n" & pass & "\n")
    let (st, dir) = fresh("again")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
    st.db.exec(sql"delete from coverage")
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
      # (the file is in the cache: no fetch)
    check st.db.getValue(sql"select count(*) from feature") == "1"
  test "a country that is not known, or that cannot be fetched, is an error and changes nothing":
    let net = Net(chile: santiago & "\n")
    let (st, dir) = fresh("unknown")
    defer:
      st.close()
    let names = newNames(st, dir, envOf(net), silent())
    expect DownloadError:
      ensureCells(names, "ZZ", box(0.2, 0.2, 0.8, 0.8))
    expect DownloadError:
      ensureCells(names, "AR", box(-65.5, -35.5, -65.2, -35.2))
        # known, but the server has no file (404)
    check st.db.getValue(sql"select count(*) from feature") == "0"
    check st.db.getValue(sql"select count(*) from coverage") == "0"
  test "a cached file that has no entry for the country is said, removed, and fetched again next time":
    let net = Net(chile: santiago & "\n")
    let (st, dir) = fresh("bad")
    defer:
      st.close()
    createDir(dir / "geonames")
    writeFile(dir / "geonames" / "CL.zip", makeZip([("other.txt", "x")]))
    var events: seq[DownloadEvent]
    let names = newNames(
      st,
      dir,
      envOf(net),
      proc(ev: DownloadEvent) {.closure, raises: [].} =
        events.add ev
      ,
    )
    expect DownloadError:
      ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
    var failed: seq[DownloadEvent]
    for e in events:
      if e.kind == deFailed:
        failed.add e
    check failed.len == 1 and "cannot be read" in failed[0].message
      # (the outlines were fetched too)
    check not fileExists(dir / "geonames" / "CL.zip")
    check st.db.getValue(sql"select count(*) from coverage") == "0"
    ensureCells(names, "CL", box(-70.7, -33.5, -70.5, -33.3))
      # the good file is fetched now
    check st.db.getValue(sql"select count(*) from feature") == "1"
