import std/[options, unittest]
import nimchoo/names/climbpick

func f(name, code: string, fromEnd: float, fromMiddle = 99999.0): Candidate =
  ## A terrain feature, or (for a P code) a populated place.
  Candidate(name: name, code: code, isPlace: code.len > 0 and code[0] == 'P' and code != "PASS" and code != "PK" and
                                             code != "PKS", fromTopM: fromEnd, fromMiddleM: fromMiddle)

suite "names: choosing a name for a climb":
  test "nothing near is no name; kinds we do not use, and places that are gone, are not names":
    check pickClimbName(@[]).isNone
    check pickClimbName(@[f("Lago", "LK", 10, 10)]).isNone
    check pickClimbName(@[f("Abandonado", "PPLQ", 10, 10), f("Destruido", "PPLW", 10, 10), f("Historico", "PPLH", 10, 10)]).isNone
  test "tier 1: within 1 km of the end, the name itself":
    let got = pickClimbName(@[f("Paso Los Libertadores", "PASS", 399)])
    check got.get.name == "Paso Los Libertadores" and got.get.kind == pkPass and got.get.tier == 1
    check pickClimbName(@[f("Cerro", "HLL", 1000)]).get.name == "Cerro"                 # (1 km exactly)
    check pickClimbName(@[f("Farellones", "PPL", 240)]).get.name == "Farellones"        # (a place is a name too, not "near")
    check pickClimbName(@[f("Cerro", "HLL", 1001)]).isNone                              # (and further is not tier 1)
  test "tier 2: within 1.5 km of the middle; 'near' from 1 km":
    check pickClimbName(@[f("Cerro", "HLL", 9999, 800)]).get.name == "Cerro"
    check pickClimbName(@[f("Cerro", "HLL", 9999, 800)]).get.tier == 2
    check pickClimbName(@[f("Cerro", "HLL", 9999, 999)]).get.name == "Cerro"
    check pickClimbName(@[f("Cerro", "HLL", 9999, 1000)]).get.name == "near Cerro"      # (1 km or more)
    check pickClimbName(@[f("Cerro", "HLL", 9999, 1500)]).get.name == "near Cerro"
    check pickClimbName(@[f("Cerro", "HLL", 9999, 1501)]).isNone
  test "tier 3: a place within 5 km of the middle, always 'near'":
    check pickClimbName(@[f("Lo Barnechea", "PPL", 9999, 100)]).get.tier == 2           # (close to the middle: tier 2, a name)
    let got = pickClimbName(@[f("Lo Barnechea", "PPL", 9999, 4999)])
    check got.get.name == "near Lo Barnechea" and got.get.tier == 3
    check pickClimbName(@[f("Lo Barnechea", "PPL", 9999, 5001)]).isNone
    check pickClimbName(@[f("Cerro", "MT", 9999, 3000)]).isNone                         # (terrain is not a last chance)
  test "a tier that gives a name wins over the next, even if the next is closer":
    # a neighbourhood 900 m from the end beats a hill 100 m from the middle
    let got = pickClimbName(@[f("Lo Contador", "PPLX", 900, 5000), f("Cerro San Cristobal", "HLL", 9999, 100)])
    check got.get.name == "Lo Contador" and got.get.tier == 1
  test "inside a tier the first kind in order wins, however far":
    let order = @[f("Paso", "PASS", 900), f("Cerro", "MT", 100), f("Loma", "HLL", 50), f("Pueblo", "PPL", 20),
                  f("Barrio", "PPLX", 10)]
    check pickClimbName(order).get.name == "Paso"                                      # a pass 900 m away beats everything nearer
    check pickClimbName(order[1 .. 4]).get.name == "Cerro"
    check pickClimbName(order[2 .. 4]).get.name == "Loma"
    check pickClimbName(order[3 .. 4]).get.name == "Pueblo"
    check pickClimbName(order[4 .. 4]).get.name == "Barrio"
    check pickClimbName(order[4 .. 4]).get.kind == pkNeighbourhood
  test "the kinds: saddle with the pass, peaks, ranges and mountains together, ridge, spur, valley and canyon with the hills":
    check pickClimbName(@[f("S", "SDL", 10)]).get.kind == pkPass
    for code in ["PK", "PKS", "MT", "MTS"]: check pickClimbName(@[f("M", code, 10)]).get.kind == pkPeak
    for code in ["HLL", "HLLS", "RDGE", "SPUR", "VAL", "CNYN"]: check pickClimbName(@[f("H", code, 10)]).get.kind == pkHill
    for code in ["PPL", "PPLA", "PPLC", "PPLL", "PPLS"]: check pickClimbName(@[f("T", code, 10)]).get.kind == pkTown
  test "the closest wins within a kind":
    let got = pickClimbName(@[f("Far", "MT", 800), f("Near", "MT", 200), f("Mid", "MTS", 500)])
    check got.get.name == "Near" and got.get.distanceM == 200
    # tier 2 and 3 are measured from the middle
    check pickClimbName(@[f("A", "PPL", 9999, 3000), f("B", "PPL", 9999, 1000), f("C", "PPL", 9999, 2000)]).get.name == "near B"
  test "the distance reported is the one that decided":
    check pickClimbName(@[f("Cerro", "HLL", 300, 50)]).get.distanceM == 300             # tier 1: from the end
    check pickClimbName(@[f("Cerro", "HLL", 9999, 700)]).get.distanceM == 700            # tier 2: from the middle
