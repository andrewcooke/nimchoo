import std/[strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/functions
import nimchoo/fold

proc folded(value: string): string =
  ## `fold()` in SQL
  let db = open(":memory:", "", "", "")
  defer:
    db.close()
  registerFunctions(db)
  db.getValue(sql"select fold(?)", value)

proc found(typed, value: string): bool =
  ## How the commands look for text in a column
  let db = open(":memory:", "", "", "")
  defer:
    db.close()
  registerFunctions(db)
  db.getValue(sql"select instr(fold(?), ?) > 0", value, foldText(typed.strip)) == "1"

suite "folding: lower case, no accents":
  test "in the program":
    check foldText("El Arrayán") == "el arrayan"
    check foldText("ÑUÑOA (2/3)") == "nunoa (2/3)"
    check foldText("Zürich") == "zurich"
    check foldText("") == ""
    check foldText("Москва") == "москва"
  test "in SQL, the same":
    for text in [
      "El Arrayán", "ÑUÑOA (2/3)", "Zürich", "", "Москва", "Peñalolén",
      "a'b",
    ]:
      check folded(text) == foldText(text)
  test "in SQL, null stays null":
    let db = open(":memory:", "", "", "")
    defer:
      db.close()
    registerFunctions(db)
    check db.getValue(sql"select fold(null) is null") == "1"
  test "SQLite's own lower() does not do it (why there is a function)":
    let db = open(":memory:", "", "", "")
    defer:
      db.close()
    check db.getValue(sql"select lower('Ñuñoa') = 'ñuñoa'") == "0"
    registerFunctions(db)
    check db.getValue(sql"select fold('Ñuñoa') = fold('ñuñoa')") == "1"

suite "folding: finding text without regard to case or accents":
  test "case does not matter, either way":
    check found("toyo", "El Toyo and back")
    check found("TOYO", "El Toyo and back")
    check found("Toyo", "el toyo")
  test "accents do not matter, either way":
    check found("arrayan", "El Arrayán and back")
    check found("Arrayán", "El Arrayan")
    check found("ARRAYÁN", "el arrayán")
    check found("nunoa", "to Ñuñoa")
    check found("ñuñoa", "Nunoa")
    check found("penalolen", "around Peñalolén")
    check found("san jose", "San José de Maipo and back")
    check found("zurich", "Zürich")
  test "it is found anywhere in the value, and not where it is not":
    check found("maipo", "San José de Maipo and back")
    check found("and back", "Lo Barnechea and back")
    check not found("toyo", "Farellones and back")
    check not found("barnechea", "")
  test "the characters of a pattern are not special in what is typed":
    check found("a*b", "xa*by")
    check not found("a*b", "axxb")
    check found("what?", "what?")
    check not found("what?", "whats")
    check found("[x]", "a [x] b")
    check found("100%", "100% sure")
    check not found("100%", "1000")
  test "other scripts are matched as typed; blanks at the ends of what is typed do not count":
    check found("Москва", "to Москва")
    check found("  toyo ", "El Toyo")
  test "typing nothing finds everything":
    check found("", "anything")
