import std/[strutils, unittest]
import nimchoo/sector/params

suite "sector: the command line":
  test "no arguments lists":
    let p = parseArgs(@[])
    check p.list and p.problem.len == 0
  test "rename and auto":
    let r = parseArgs(@["--edit", "Morro La Cabra (1/3)", "--rename", "  La Cabra  "])
    check r.problem.len == 0 and r.edit and not r.list and r.name == "Morro La Cabra (1/3)" and r.rename == "La Cabra"
    let a = parseArgs(@["--edit", "X", "--auto"])
    check a.problem.len == 0 and a.edit and a.auto
  test "mistakes":
    check parseArgs(@["--edit", "X"]).problem.contains("something to change")
    check parseArgs(@["--edit", "X", "--rename", "Y", "--auto"]).problem.contains("cannot be used together")
    check parseArgs(@["--rename", "Y"]).problem.contains("go with --edit")
    check parseArgs(@["--auto"]).problem.contains("go with --edit")
    check parseArgs(@["--edit", " ", "--auto"]).problem.contains("needs the name")
    check parseArgs(@["Cerro"]).problem.contains("--edit Cerro --rename NEW")
  test "names that are refused":
    check nameProblem("Cerro Calán") == ""
    check nameProblem("  ").contains("empty")
    check nameProblem("x".repeat(61)).contains("at most")
    check nameProblem("a\nb").contains("control")
    check nameProblem("Cuesta (2/3)").contains("(n/m)")
    check nameProblem("Cuesta (the 2/3 one)") == ""
    check parseArgs(@["--edit", "X", "--rename", "Cuesta (2/3)"]).problem.contains("(n/m)")
  test "looking numbered":
    check looksNumbered("A (1/2)") and looksNumbered("A B (10/12)")
    check not looksNumbered("A (1)") and not looksNumbered("A(1/2)") and not looksNumbered("(1/2)") and not looksNumbered("A (/2)")
