import nimchoo/db/statement
import std/[options, os, unittest]
import nimchoo/db/store
import nimchoo/core/errors
import nimchoo/landmark/[landmarks, suggest]
import nimchoo/modules

proc fresh(name: string): Store =
  let top = getTempDir() / "nch-test-landmark" / name
  removeDir(top)
  openStore(top / "x.db", allFragments)

proc feature(s: Store, id: int, name, cls, code: string, lon, lat: float, pop = 0) =
  s.db.execute(
    "insert or ignore into country(iso, name, geoname_id) values ('CL', 'Chile', 1)"
  )
  s.db.execute(
    "insert into feature(id, country, name, class, code, population, geom) values (:id, 'CL', :name, :class, :code, :population, MakePoint(cast(:lon as real), cast(:lat as real), 4326))",
    id = id,
    name = name,
    class = cls,
    code = code,
    population = pop,
    lon = lon,
    lat = lat,
  )

suite "landmark: the landmarks":
  test "make, list (by name), find the one that holds a position, remove":
    let s = fresh("basic")
    defer:
      s.close()
    addLandmark(s, "Yerba Loca", -70.364, -33.344, 1000.0)
    addLandmark(s, "casa", -70.6, -33.4, 500.0)
    check s.listLandmarks().len == 2
    check s.listLandmarks()[0].name == "casa" # (by name without regard to case)
    let at = s.landmarkAt(-70.3645, -33.3445)
    check at.isSome and at.get.landmark.name == "Yerba Loca" and at.get.distanceM < 100.0
    check s.landmarkAt(-70.364, -33.36).isNone # 1.8 km away: outside the 1 km circle
    check s.removeLandmark("YERBA loca")
    check not s.removeLandmark("Yerba Loca")
    check s.listLandmarks().len == 1
  test "names are the same without regard to accents or capitals, not only ASCII ones":
    let s = fresh("accents")
    defer:
      s.close()
    addLandmark(s, "Ñuñoa", -70.6, -33.45, 500.0)
    expect StoreError:
      addLandmark(s, "ñuñoa", -70.5, -33.4, 500.0)
    expect StoreError:
      addLandmark(s, "NUNOA", -70.5, -33.4, 500.0)
    check s.removeLandmark("ñUÑOA")
    check s.listLandmarks().len == 0
  test "the radius is a circle in metres: a position at 900 m is in, at 1,100 m is out":
    let s = fresh("circle")
    defer:
      s.close()
    addLandmark(s, "A", 0.0, 0.0, 1000.0)
    check s.landmarkAt(0.0, 900.0 / 111_195.0).isSome
    check s.landmarkAt(0.0, 1100.0 / 111_195.0).isNone
  test "when circles overlap the nearer centre wins":
    let s = fresh("overlap")
    defer:
      s.close()
    addLandmark(s, "far", 0.0, 0.0, 5000.0)
    addLandmark(s, "near", 0.02, 0.0, 5000.0)
    check s.landmarkAt(0.018, 0.0).get.landmark.name == "near"
  test "a name is used once (without regard to case); bad names, positions and radii are refused":
    let s = fresh("refuse")
    defer:
      s.close()
    addLandmark(s, "A", 1.0, 1.0, 1000.0)
    expect StoreError:
      addLandmark(s, "a", 2.0, 2.0, 1000.0)
    expect StoreError:
      addLandmark(s, " ", 2.0, 2.0, 1000.0)
    expect StoreError:
      addLandmark(s, "B", 200.0, 2.0, 1000.0)
    expect StoreError:
      addLandmark(s, "B", 2.0, 100.0, 1000.0)
    expect StoreError:
      addLandmark(s, "B", 2.0, 2.0, 50.0)
    check s.listLandmarks().len == 1

suite "landmark: suggestions":
  test "by part of the name, without regard to case, the biggest places first":
    let s = fresh("search")
    defer:
      s.close()
    s.feature(1, "Estero de la Yerba Loca", "H", "STM", -70.364, -33.344)
    s.feature(2, "Cerro Yerba Loca", "T", "MT", -70.6, -29.7)
    s.feature(3, "Yerba Loca", "P", "PPL", -70.0, -33.0, pop = 500)
    s.feature(4, "Santiago", "P", "PPLC", -70.65, -33.45, pop = 4_000_000)
    let found = s.searchByName("yerba LOCA")
    check found.len == 3 and found[0].name == "Yerba Loca" and
      found[1].name == "Cerro Yerba Loca"
    check found[2].cls == "H" and found[2].code == "STM" and
      abs(found[2].lon + 70.364) < 1e-9
    check s.searchByName("zzz").len == 0
    s.feature(6, "Ñuñoa", "P", "PPL", -70.6, -33.45)
    check s.searchByName("ñUÑOA").len == 1 and s.searchByName("nunoa").len == 1
    check s.searchByName("100%").len == 0 # (% and _ are not wildcards)
    s.feature(5, "100% Chile", "S", "HSE", -70.0, -33.0)
    check s.searchByName("100%").len == 1
  test "round a position, nearest first, within the radius":
    let s = fresh("near")
    defer:
      s.close()
    s.feature(1, "El Toyo", "S", "FRM", -70.34947, -33.68255)
    s.feature(2, "Lo Flores", "L", "LCTY", -70.34, -33.69)
    s.feature(3, "El Melocotón", "P", "PPLX", -70.33, -33.69)
    s.feature(4, "Far away", "P", "PPL", -70.0, -33.0)
    let found = s.featuresAround(-70.34304, -33.68009)
    check found.len == 3 and found[0].name == "El Toyo" and found[1].name == "Lo Flores"
    check found[0].distanceM > 600.0 and found[0].distanceM < 700.0
    check s.featuresAround(-70.34304, -33.68009, 800.0).len == 1
    check s.featuresAround(10.0, 10.0).len == 0
  test "negative and high latitudes and the date line":
    let s = fresh("edges")
    defer:
      s.close()
    s.feature(1, "Beyond", "T", "MT", -179.99, 65.0)
    s.feature(2, "South", "T", "MT", 10.0, -75.0)
    check s.featuresAround(-179.99, 65.0, 500.0).len == 1
    check s.featuresAround(10.0, -75.0, 500.0).len == 1
