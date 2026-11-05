import std/[options, unittest]
import nimchoo/names/pick

func terrain(name, code: string, fromTop: float): Candidate =
  Candidate(name: name, code: code, fromTopM: fromTop, fromMiddleM: 99999.0)

func town(name: string, fromMiddle: float, fromTop = 99999.0): Candidate =
  Candidate(name: name, code: "PPL", isPlace: true, fromTopM: fromTop, fromMiddleM: fromMiddle)

suite "names: choosing a name for a climb":
  test "nothing near is no name":
    check pickName(@[]).isNone
    check pickName(@[terrain("Lago", "LK", 10)]).isNone                    # (not a kind we use)
  test "a pass beats a peak beats a hill beats a town":
    let all = @[town("Lo Barnechea", 100), terrain("Cerro Calan", "HLL", 50),
                terrain("Cerro Manquehue", "MT", 300), terrain("Paso Los Libertadores", "PASS", 100)]
    check pickName(all).get.name == "Paso Los Libertadores" and pickName(all).get.kind == pkPass
    check pickName(all[0 .. 2]).get.name == "Cerro Manquehue" and pickName(all[0 .. 2]).get.kind == pkPeak
    check pickName(all[0 .. 1]).get.name == "Cerro Calan" and pickName(all[0 .. 1]).get.kind == pkHill
    check pickName(all[0 .. 0]).get.name == "near Lo Barnechea" and pickName(all[0 .. 0]).get.kind == pkNear
  test "the radii: a pass 400 m from the top, a peak 1 km, a hill 1.5 km, a town 5 km from the middle":
    check pickName(@[terrain("P", "PASS", 399)]).get.kind == pkPass
    check pickName(@[terrain("P", "PASS", 401)]).isNone
    check pickName(@[terrain("S", "SDL", 100)]).get.kind == pkPass
    check pickName(@[terrain("M", "MT", 999)]).get.kind == pkPeak
    check pickName(@[terrain("M", "PK", 1001)]).isNone
    check pickName(@[terrain("H", "HLL", 1499)]).get.kind == pkHill
    check pickName(@[terrain("H", "HLL", 1499)]).get.name == "near H"
    check pickName(@[terrain("H", "RDGE", 1501)]).isNone
    check pickName(@[town("T", 4999)]).get.kind == pkNear
    check pickName(@[town("T", 5001)]).isNone
  test "terrain is measured from the top only, a place from the middle only":
    # a mountain close to the middle or the bottom of the climb but far from its top is not its name
    check pickName(@[Candidate(name: "Cerro", code: "MT", fromTopM: 3000, fromMiddleM: 10)]).isNone
    # a town close to the top but far from the middle is not "near" the climb
    check pickName(@[town("Farellones", 6000, fromTop = 100)]).isNone
    check pickName(@[town("Farellones", 4000, fromTop = 100)]).get.name == "near Farellones"
  test "a pass too far from the top does not stop a nearer peak being used":
    let got = pickName(@[terrain("Paso", "PASS", 900), terrain("Cerro", "PK", 500)])
    check got.get.name == "Cerro" and got.get.distanceM == 500
  test "a feature more than 1 km away is only near the climb":
    check pickName(@[terrain("Cerro", "HLL", 1000)]).get.name == "Cerro"             # (1 km exactly: the name)
    check pickName(@[terrain("Cerro", "HLL", 1001)]).get.name == "near Cerro"
    check pickName(@[terrain("Cerro", "HLL", 1001)]).get.kind == pkHill              # (the kind is still a hill)
    check pickName(@[terrain("Cerro", "MT", 999)]).get.name == "Cerro"
    check pickName(@[terrain("Paso", "PASS", 399)]).get.name == "Paso"
    check pickName(@[town("Lo Barnechea", 50)]).get.name == "near Lo Barnechea"      # (a town is always "near")
  test "the nearest wins within a kind":
    let got = pickName(@[terrain("Far", "MT", 800), terrain("Near", "MT", 200), terrain("Mid", "MTS", 500)])
    check got.get.name == "Near" and got.get.distanceM == 200
    check pickName(@[town("A", 3000), town("B", 1000), town("C", 2000)]).get.name == "near B"
