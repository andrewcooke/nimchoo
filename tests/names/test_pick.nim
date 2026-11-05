import std/[options, unittest]
import nimchoo/names/pick

func terrain(name, code: string, fromTop, fromRoute: float): Candidate =
  Candidate(name: name, code: code, fromTopM: fromTop, fromRouteM: fromRoute)

func town(name: string, fromRoute: float): Candidate =
  Candidate(name: name, code: "PPL", isPlace: true, fromTopM: fromRoute + 100, fromRouteM: fromRoute)

suite "names: choosing a name for a climb":
  test "nothing near is no name":
    check pickName(@[]).isNone
    check pickName(@[terrain("Lago", "LK", 10, 10)]).isNone               # (not a kind we use)
  test "a pass beats a peak beats a hill beats a town":
    let all = @[town("Lo Barnechea", 100), terrain("Cerro Calan", "HLL", 50, 40),
                terrain("Cerro Manquehue", "MT", 300, 200), terrain("Paso Los Libertadores", "PASS", 100, 100)]
    check pickName(all).get.name == "Paso Los Libertadores" and pickName(all).get.kind == pkPass
    check pickName(all[0 .. 2]).get.name == "Cerro Manquehue" and pickName(all[0 .. 2]).get.kind == pkPeak
    check pickName(all[0 .. 1]).get.name == "Cerro Calan" and pickName(all[0 .. 1]).get.kind == pkHill
    check pickName(all[0 .. 0]).get.name == "near Lo Barnechea" and pickName(all[0 .. 0]).get.kind == pkNear
  test "the radii: a pass 400 m from the top, a peak 1 km from the top, a hill 1.5 km from the route, a town 5 km":
    check pickName(@[terrain("P", "PASS", 399, 0)]).get.kind == pkPass
    check pickName(@[terrain("P", "PASS", 401, 0)]).isNone
    check pickName(@[terrain("S", "SDL", 100, 0)]).get.kind == pkPass
    check pickName(@[terrain("M", "MT", 999, 5000)]).get.kind == pkPeak          # (measured from the top)
    check pickName(@[terrain("M", "PK", 1001, 0)]).isNone
    check pickName(@[terrain("H", "HLL", 9000, 1499)]).get.kind == pkHill        # (measured from the route)
    check pickName(@[terrain("H", "HLL", 9000, 1499)]).get.name == "near H"
    check pickName(@[terrain("H", "RDGE", 0, 1501)]).isNone
    check pickName(@[town("T", 4999)]).get.kind == pkNear
    check pickName(@[town("T", 5001)]).isNone
  test "a pass too far from the top does not stop a nearer peak being used":
    let got = pickName(@[terrain("Paso", "PASS", 900, 10), terrain("Cerro", "PK", 500, 400)])
    check got.get.name == "Cerro" and got.get.distanceM == 500
  test "a feature more than 1 km away is only near the climb":
    check pickName(@[terrain("Cerro", "HLL", 0, 1000)]).get.name == "Cerro"            # (1 km exactly: the name)
    check pickName(@[terrain("Cerro", "HLL", 0, 1001)]).get.name == "near Cerro"
    check pickName(@[terrain("Cerro", "HLL", 0, 1001)]).get.kind == pkHill             # (the kind is still a hill)
    check pickName(@[terrain("Cerro", "MT", 999, 0)]).get.name == "Cerro"
    check pickName(@[terrain("Paso", "PASS", 399, 0)]).get.name == "Paso"
    check pickName(@[town("Lo Barnechea", 50)]).get.name == "near Lo Barnechea"        # (a town is always "near")
  test "the nearest wins within a kind":
    let got = pickName(@[terrain("Far", "MT", 800, 0), terrain("Near", "MT", 200, 0), terrain("Mid", "MTS", 500, 0)])
    check got.get.name == "Near" and got.get.distanceM == 200
    check pickName(@[town("A", 3000), town("B", 1000), town("C", 2000)]).get.name == "near B"
