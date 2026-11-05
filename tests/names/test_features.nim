import std/[options, os, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/store
import nimchoo/download/fetch
import nimchoo/names/[countries, features]
import ../support/[namesdata, zips]

suite "names: a line of a GeoNames file":
  test "terrain of the kinds we want, and populated places":
    let f = parseFeature(sanCristobal)
    check f.isSome and f.get.id == 3871427 and f.get.name == "Cerro San Cristóbal"
    check f.get.cls == "T" and f.get.code == "HLL" and abs(f.get.lat + 33.42) < 1e-9 and abs(f.get.lon + 70.63) < 1e-9
    let p = parseFeature(santiago)
    check p.isSome and p.get.population == 4837295 and p.get.code == "PPLC"
    check parseFeature(pass).get.code == "PASS"
    check parseFeature(barrio).get.population == 0
  test "water, roads, islands and other kinds are left out; so are short and broken lines":
    check parseFeature(lake).isNone and parseFeature(road).isNone and parseFeature(island).isNone
    check parseFeature("").isNone
    check parseFeature("1\tName\tName\t\t-33.4\t-70.6\tT").isNone              # cut short
    check parseFeature(gn(5, "", -33.0, -70.0, "P", "PPL")).isNone           # no name
    check parseFeature(gn(6, "X", -33.0, -70.0, "P", "PPL").replace("-33.0", "north")).isNone
  test "the terrain codes kept":
    for code in terrainCodes:
      check parseFeature(gn(7, "X", 1.0, 2.0, "T", code)).isSome

suite "names: loading a country":
  test "the file is fetched once, the wanted features are read in, and the country is recorded":
    let net = Net(chile: [santiago, sanCristobal, pass, lake, road, island, barrio, "garbage line"].join("\n") & "\n")
    let (st, dir) = fresh("load")
    defer: st.close()
    let names = newNames(st, dir, envOf(net), silent())
    check ensureNames(names, "CL")
    check st.db.getValue(sql"select count(*) from feature") == "4"           # Santiago, the hill, the pass, Lo Barnechea
    check st.db.getValue(sql"select features from name_source where country = 'CL'") == "4"
    check st.db.getValue(sql"select name from feature where code = 'PASS'") == "Paso Los Libertadores"
    check st.db.getValue(sql"select count(*) from feature where country = 'CL'") == "4"
    # the spatial index finds a feature by a box
    check st.db.getValue(sql"""select name from feature where id in (select ROWID from SpatialIndex
        where f_table_name = 'feature' and f_geometry_column = 'geom' and
              search_frame = BuildMbr(-70.2, -32.9, -70.0, -32.7))""") == "Paso Los Libertadores"
    let gets = net.gets.len
    check ensureNames(names, "CL")
    check net.gets.len == gets                                                # nothing more fetched
    check st.db.getValue(sql"select count(*) from feature") == "4"

  test "loading again after the table was emptied does not double anything":
    let net = Net(chile: santiago & "\n" & pass & "\n")
    let (st, dir) = fresh("again")
    defer: st.close()
    let names = newNames(st, dir, envOf(net), silent())
    check ensureNames(names, "CL")
    st.db.exec(sql"delete from name_source")
    check ensureNames(names, "CL")                    # (the file is in the cache: no fetch)
    check st.db.getValue(sql"select count(*) from feature") == "2"

  test "a country that is not known, or that cannot be fetched, is false and changes nothing":
    let net = Net(chile: santiago & "\n")
    let (st, dir) = fresh("unknown")
    defer: st.close()
    let names = newNames(st, dir, envOf(net), silent())
    check not ensureNames(names, "ZZ")
    check not ensureNames(names, "AR")                # known, but the server has no file (404)
    check st.db.getValue(sql"select count(*) from feature") == "0"
    check st.db.getValue(sql"select count(*) from name_source") == "0"

  test "a cached file that has no entry for the country is said, removed, and fetched again next time":
    let net = Net(chile: santiago & "\n")
    let (st, dir) = fresh("bad")
    defer: st.close()
    createDir(dir / "geonames")
    writeFile(dir / "geonames" / "CL.zip", makeZip([("other.txt", "x")]))
    var events: seq[DownloadEvent]
    let names = newNames(st, dir, envOf(net), proc(ev: DownloadEvent) {.closure, raises: [].} = events.add ev)
    check not ensureNames(names, "CL")
    var failed: seq[DownloadEvent]
    for e in events:
      if e.kind == deFailed: failed.add e
    check failed.len == 1 and "cannot be read" in failed[0].message          # (the outlines were fetched too)
    check not fileExists(dir / "geonames" / "CL.zip")
    check st.db.getValue(sql"select count(*) from name_source") == "0"
    check ensureNames(names, "CL")                        # the good file is fetched now
    check st.db.getValue(sql"select count(*) from feature") == "1"
