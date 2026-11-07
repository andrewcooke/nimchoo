import std/[strutils, unittest]
import db_connector/db_sqlite
import nimchoo/selection/fold

proc matches(pattern, value: string): bool =
  let db = open(":memory:", "", "", "")
  defer:
    db.close()
  db.getValue(sql"select ? glob ?", value, pattern) == "1"

suite "list: finding text without regard to case or accents":
  test "case does not matter, either way":
    check matches(foldGlob("toyo"), "El Toyo and back")
    check matches(foldGlob("TOYO"), "El Toyo and back")
    check matches(foldGlob("Toyo"), "el toyo")
  test "accents do not matter, either way":
    check matches(foldGlob("arrayan"), "El Arrayán and back")
    check matches(foldGlob("Arrayán"), "El Arrayan")
    check matches(foldGlob("ARRAYÁN"), "el arrayán")
    check matches(foldGlob("nunoa"), "to Ñuñoa")
    check matches(foldGlob("ñuñoa"), "Nunoa")
    check matches(foldGlob("penalolen"), "around Peñalolén")
    check matches(foldGlob("san jose"), "San José de Maipo and back")
    check matches(foldGlob("zurich"), "Zürich")
  test "it is found anywhere in the value, and not where it is not":
    check matches(foldGlob("maipo"), "San José de Maipo and back")
    check matches(foldGlob("and back"), "Lo Barnechea and back")
    check not matches(foldGlob("toyo"), "Farellones and back")
    check not matches(foldGlob("barnechea"), "")
  test "the characters of a pattern are not special in what is typed":
    check matches(foldGlob("a*b"), "xa*by")
    check not matches(foldGlob("a*b"), "axxb")
    check matches(foldGlob("what?"), "what?")
    check not matches(foldGlob("what?"), "whats")
    check matches(foldGlob("[x]"), "a [x] b")
    check matches(foldGlob("near "), "near Santiago")
  test "other scripts are matched as typed; blanks at the ends do not count":
    check matches(foldGlob("Москва"), "to Москва")
    check matches(foldGlob("  toyo "), "El Toyo")
  test "the pattern for nothing matches everything":
    check matches(foldGlob(""), "anything")

suite "list: folding in the program":
  test "lower case, no accents":
    check foldText("El Arrayán") == "el arrayan"
    check foldText("ÑUÑOA (2/3)") == "nunoa (2/3)"
    check foldText("Zürich") == "zurich"
    check foldText("") == ""
    check foldText("Москва") == "москва"
  test "it agrees with the pattern: what the pattern finds, the folded text contains":
    for (value, typed) in [
      ("San José de Maipo", "san jose"),
      ("Peñalolén", "PENALOLEN"),
      ("Cerro Calán (1/2)", "calan (1"),
    ]:
      check foldText(value).contains(foldText(typed))
