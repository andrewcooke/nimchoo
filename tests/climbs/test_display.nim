import std/unittest
import nimchoo/climbs/display

func s(id: int64, name: string, n: int): Shown = Shown(id: id, name: name, n: n)

suite "climbs display: names with a kept number as a subscript":
  test "a name used once is shown plain, whatever its number":
    check displayNames([s(1, "Cerro Calán", 1)]) == @["Cerro Calán"]
    check displayNames([s(1, "Cerro Calán", 4)]) == @["Cerro Calán"]
  test "nothing at all":
    check displayNames(newSeq[Shown]()).len == 0
  test "shared names show their own kept number, in the order given":
    check displayNames([s(1, "La Dehesa", 1), s(2, "La Dehesa", 3), s(3, "La Dehesa", 2)]) ==
      @["La Dehesa₁", "La Dehesa₃", "La Dehesa₂"]
  test "the number is the climb's own: a gap stays a gap":
    check displayNames([s(1, "A", 1), s(3, "A", 3)]) == @["A₁", "A₃"]
  test "case does not matter for the group, each keeps its own spelling":
    check displayNames([s(1, "la dehesa", 1), s(2, "La Dehesa", 2)]) == @["la dehesa₁", "La Dehesa₂"]
  test "different names are separate groups":
    check displayNames([s(1, "A", 1), s(2, "B", 1), s(3, "A", 2)]) == @["A₁", "B", "A₂"]
  test "no name is unnamed, and unnamed climbs are numbered too":
    check displayNames([s(1, "", 1)]) == @["unnamed"]
    check displayNames([s(1, "", 1), s(2, "  ", 2), s(3, "Unnamed", 3)]) == @["unnamed₁", "unnamed₂", "Unnamed₃"]
  test "a number of several digits":
    check subscriptNumber(0) == "₀" and subscriptNumber(12) == "₁₂" and subscriptNumber(907) == "₉₀₇"

suite "climbs display: reading what a person types":
  test "a number at the end is also read as a subscript; the text as typed is kept too":
    check ordinalForms("Farellones 3") == @["Farellones 3", "Farellones₃"]
    check ordinalForms("farellones3") == @["farellones3", "farellones₃"]
    check ordinalForms("  Farellones   12 ") == @["Farellones   12", "Farellones₁₂"]
    check ordinalForms("Farellones₃") == @["Farellones₃"]
    check ordinalForms("Farellones") == @["Farellones"]
    check ordinalForms("3") == @["3"]                                  # (a number on its own is not a number of something)
    check ordinalForms("Ruta 60") == @["Ruta 60", "Ruta₆₀"]            # (a name can really end in a number: both are tried)
  test "the subscript at the end of a name, and without it":
    check endsWithSubscript("Farellones₃") and endsWithSubscript("A₁₂")
    check not endsWithSubscript("Farellones") and not endsWithSubscript("Farellones 3") and not endsWithSubscript("")
    check withoutSubscript("Morro La Cabra₁₂") == "Morro La Cabra" and withoutSubscript("Plain") == "Plain"
