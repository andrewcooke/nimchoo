import std/unittest
import nimchoo/climbs/display

func s(id: int64, name: string, gain: float): Shown = Shown(id: id, name: name, gainM: gain)

suite "climbs display: names with (n/m)":
  test "a name used once is shown plain":
    check displayNames([s(1, "Cerro Calán", 120)]) == @["Cerro Calán"]
  test "nothing at all":
    check displayNames(newSeq[Shown]()).len == 0
  test "shared names are numbered by gain, the biggest first, in the order given":
    check displayNames([s(1, "La Dehesa", 100), s(2, "La Dehesa", 300), s(3, "La Dehesa", 200)]) ==
      @["La Dehesa (3/3)", "La Dehesa (1/3)", "La Dehesa (2/3)"]
  test "ties go by id":
    check displayNames([s(9, "A", 100), s(4, "A", 100)]) == @["A (2/2)", "A (1/2)"]
  test "case does not matter for the group, each keeps its own spelling":
    check displayNames([s(1, "la dehesa", 90), s(2, "La Dehesa", 150)]) == @["la dehesa (2/2)", "La Dehesa (1/2)"]
  test "different names are separate groups":
    check displayNames([s(1, "A", 100), s(2, "B", 200), s(3, "A", 50)]) == @["A (1/2)", "B", "A (2/2)"]
  test "no name is unnamed, and unnamed climbs are numbered too":
    check displayNames([s(1, "", 100)]) == @["unnamed"]
    check displayNames([s(1, "", 100), s(2, "  ", 200), s(3, "Unnamed", 150)]) ==
      @["unnamed (3/3)", "unnamed (1/3)", "Unnamed (2/3)"]
  test "the group closes up when a climb is renamed":
    check displayNames([s(1, "A", 100), s(2, "A", 200), s(3, "A", 300)]) == @["A (3/3)", "A (2/3)", "A (1/3)"]
    check displayNames([s(1, "A", 100), s(2, "A", 200), s(3, "B", 300)]) == @["A (2/2)", "A (1/2)", "B"]
