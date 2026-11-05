import std/[os, unittest]
import db_connector/db_sqlite
import nimchoo/cli/common
import nimchoo/db/store
import nimchoo/empty/command as emptyCommand
import nimchoo/modules
import ../support/userdata

let dir = getTempDir() / "nch-test-empty"

proc fresh(name: string): string =
  result = dir / name
  removeDir(result)
  createDir(result)

suite "empty --all: the whole database":
  test "without --force nothing happens":
    let d = fresh("noforce")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @["--all"]) == exitFailure
    check fileExists(d / "x.db")

  test "with --force the file and its journal files go":
    let d = fresh("force")
    openStore(d / "x.db", allFragments).close()
    writeFile(d / "x.db-journal", "")
    check emptyCommand.run(globals(d / "x.db"), @["--all", "-f"]) == exitOk
    check not fileExists(d / "x.db")
    check not fileExists(d / "x.db-journal")

  test "no database: nothing to do, and nothing is created":
    let d = fresh("none")
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--force"]) == exitOk
    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob", "--force"]) == exitOk
    check not fileExists(d / "x.db")

suite "empty: what to empty is named":
  test "there is no default: a target is needed; --all holds the rest, so it stands alone (with --names and --cache)":
    let d = fresh("target")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @[]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--user", "bob", "-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--sectors", "-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db"), @["--data", "-f"]) == exitUsage                # (there is no --data)
    check fileExists(d / "x.db")

  test "--user before the command is refused, with a hint":
    let d = fresh("globaluser")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--all", "-f"]) == exitUsage
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--user", "bob", "-f"]) == exitUsage
    check fileExists(d / "x.db")

  test "bad arguments are a usage error":
    check emptyCommand.run(globals("x"), @["--bogus"]) == exitUsage
    check emptyCommand.run(globals("x"), @["--help"]) == exitOk

suite "empty --user: one user's data":
  test "the user stays; their data and only theirs go":
    let d = fresh("user")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.close()
    addUser(d / "x.db", "bob")
    let bob = openStore(d / "x.db", allFragments, "bob")
    fill(bob, "bobs")
    bob.db.exec(sql"insert into user_profile(user_id, fthr) values (?, 150)", bob.userId)
    bob.close()

    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob"]) == exitFailure       # no -f
    let before = openStore(d / "x.db", allFragments)
    for t in tables: check before.count(t) == 2
    before.close()

    check emptyCommand.run(globals(d / "x.db"), @["--user", "bob", "-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    for t in tables: check after.count(t) == 1
    check after.db.getValue(sql"select count(*) from user where name = 'bob'") == "1"
    check after.db.getValue(sql"select name from file") == "mine"
    check after.db.getValue(sql"select fthr from user_profile") == "150"

  test "an unknown user is an error":
    let d = fresh("unknown")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @["--user", "nobody", "-f"]) == exitFailure

suite "empty --cache: the files commands made":
  test "the generated files go; the unpacked ones and the token stay; no -f needed":
    let d = fresh("cache")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "user")
    createDir(d / "cache" / "system")
    writeFile(d / "cache" / "user" / "heatmap--key-ab.geojson", "{}")
    writeFile(d / "cache" / "user" / "ff--key-cd.csv", "time\n")
    writeFile(d / "cache" / "system" / "libraries.txt", "x")
    writeFile(d / "cache" / "server-token", "secret")
    check emptyCommand.run(globals(d / "none.db"), @["--cache"]) == exitOk
    check not fileExists(d / "cache" / "user" / "heatmap--key-ab.geojson")
    check not fileExists(d / "cache" / "user" / "ff--key-cd.csv")
    check fileExists(d / "cache" / "system" / "libraries.txt")
    check fileExists(d / "cache" / "server-token")
    check not fileExists(d / "none.db")            # (the database is not touched, or made)
    check emptyCommand.run(globals(d / "none.db"), @["--cache"]) == exitOk      # nothing left: fine

suite "empty --sectors: the catalogue of climbs":
  test "the sectors, the efforts on them (of every user) and the record go; the rides stay":
    let d = fresh("sectors")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    let act = a.db.getValue(sql"select id from activity")
    a.db.exec(sql"insert into effort(sector_id, activity_id, start_t, finish_t, elapsed_s, start_m) values (1, ?, 1, 61, 60, 0)", act)
    a.db.exec(sql"insert into climbs_done(activity_id, version) values (?, 1)", act)
    a.close()
    check emptyCommand.run(globals(d / "x.db"), @["--sectors"]) == exitFailure          # no -f
    let before = openStore(d / "x.db", allFragments)
    check before.count("sector") == 1 and before.count("effort") == 1
    before.close()
    check emptyCommand.run(globals(d / "x.db"), @["--sectors", "-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    check after.count("sector") == 0 and after.count("effort") == 0 and after.count("climbs_done") == 0
    check after.count("activity") == 1 and after.count("file") == 1

  test "--user before the command is refused here too":
    let d = fresh("sectorsuser")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db", "bob"), @["--sectors", "-f"]) == exitUsage

suite "empty --names: the place names and countries, tables and downloaded files":
  test "the tables are emptied and the GeoNames files deleted; other downloads, the generated files and the names given to climbs stay":
    let d = fresh("names")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "data" / "geonames")
    createDir(d / "cache" / "data" / "elsewhere")
    createDir(d / "cache" / "user")
    writeFile(d / "cache" / "data" / "geonames" / "CL.zip", "zip")
    writeFile(d / "cache" / "data" / "elsewhere" / "tile.bin", "tile")
    writeFile(d / "cache" / "user" / "heatmap--key-ab.geojson", "{}")
    let st = openStore(d / "x.db", allFragments)
    st.db.exec(sql"insert into country(iso, name, geoname_id) values ('CL', 'Chile', 3895114)")
    st.db.exec(sql"insert into coverage(country, cell_lon, cell_lat, loaded_at, features) values ('CL', -71, -34, 1, 1)")
    st.db.exec(sql"insert into feature(id, country, name, class, code, geom) values (1, 'CL', 'Cerro', 'T', 'HLL', MakePoint(-70.6, -33.4, 4326))")
    st.db.exec(sql"insert into sector(length_m, gain_m, gradient, name) values (1000, 50, 5, 'Cerro')")
    st.close()
    check emptyCommand.run(globals(d / "x.db"), @["--names"]) == exitFailure          # no -f
    check fileExists(d / "cache" / "data" / "geonames" / "CL.zip")
    check emptyCommand.run(globals(d / "x.db"), @["--names", "-f"]) == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    check after.count("feature") == 0 and after.count("coverage") == 0 and after.count("country") == 0
    check after.db.getValue(sql"select name from sector") == "Cerro"
    check not dirExists(d / "cache" / "data" / "geonames")
    check fileExists(d / "cache" / "data" / "elsewhere" / "tile.bin")
    check fileExists(d / "cache" / "user" / "heatmap--key-ab.geojson")
    check emptyCommand.run(globals(d / "x.db"), @["--names", "-f"]) == exitOk          # nothing left: fine

suite "empty: several things at once":
  test "one message, one countdown, one done; and without -f none of them is done":
    let d = fresh("several")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "data" / "geonames")
    createDir(d / "cache" / "user")
    writeFile(d / "cache" / "data" / "geonames" / "CL.zip", "zip")
    writeFile(d / "cache" / "user" / "heatmap--key-ab.geojson", "{}")
    let a = openStore(d / "x.db", allFragments)
    fill(a, "mine")
    a.db.exec(sql"insert into sector(length_m, gain_m, gradient, name) values (1000, 50, 5, 'Cerro')")
    a.db.exec(sql"insert into country(iso, name, geoname_id) values ('CL', 'Chile', 3895114)")
    a.close()
    let everything = @["--user", defaultUser, "--sectors", "--names", "--cache"]
    check emptyCommand.run(globals(d / "x.db"), everything) == exitFailure         # no -f: none of it
    let before = openStore(d / "x.db", allFragments)
    check before.count("activity") == 1 and before.count("sector") == 1 and before.count("country") == 1
    before.close()
    check fileExists(d / "cache" / "data" / "geonames" / "CL.zip")
    check fileExists(d / "cache" / "user" / "heatmap--key-ab.geojson")
    check emptyCommand.run(globals(d / "x.db"), everything & "-f") == exitOk
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    check after.count("file") == 0 and after.count("activity") == 0         # the user's data
    check after.count("sector") == 0 and after.count("country") == 0           # the climbs, the names
    check after.count("user") == 1                                              # (the user stays)
    check not dirExists(d / "cache" / "data" / "geonames")
    check not fileExists(d / "cache" / "user" / "heatmap--key-ab.geojson")

  test "an unknown user is found out before anything is done":
    let d = fresh("severalbad")
    let a = openStore(d / "x.db", allFragments)
    a.db.exec(sql"insert into sector(length_m, gain_m, gradient) values (1000, 50, 5)")
    a.close()
    check emptyCommand.run(globals(d / "x.db"), @["--sectors", "--user", "nobody", "-f"]) == exitFailure
    let after = openStore(d / "x.db", allFragments)
    defer: after.close()
    check after.count("sector") == 1

  test "--all goes with --names and --cache (the downloaded and the generated files)":
    let d = fresh("allfiles")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "data" / "geonames")
    createDir(d / "cache" / "user")
    writeFile(d / "cache" / "data" / "geonames" / "CL.zip", "zip")
    writeFile(d / "cache" / "user" / "a.geojson", "{}")
    openStore(d / "x.db", allFragments).close()
    check emptyCommand.run(globals(d / "x.db"), @["--all", "--names", "--cache", "-f"]) == exitOk
    check not fileExists(d / "x.db")
    check not dirExists(d / "cache" / "data" / "geonames")
    check not fileExists(d / "cache" / "user" / "a.geojson")

  test "with no database the files can still be emptied":
    let d = fresh("nodb")
    putEnv("NCH_CACHE", d / "cache")
    defer: delEnv("NCH_CACHE")
    createDir(d / "cache" / "data" / "geonames")
    writeFile(d / "cache" / "data" / "geonames" / "CL.zip", "zip")
    check emptyCommand.run(globals(d / "none.db"), @["--sectors", "--names", "-f"]) == exitOk
    check not dirExists(d / "cache" / "data" / "geonames")
    check not fileExists(d / "none.db")
