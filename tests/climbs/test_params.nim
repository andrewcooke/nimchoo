import std/[strutils, unittest]
import nimchoo/climbs/params

suite "climbs: the command line":
  test "no arguments: the climbs of the selected activities; --all: every climb":
    let p = parseArgs(@[])
    check p.problem.len == 0 and not p.all and not p.edit and not p.listOnly
    let a = parseArgs(@["--all"])
    check a.problem.len == 0 and a.all and not a.listOnly
  test "rename and auto":
    let r = parseArgs(@["--edit", "Morro La Cabra (1/3)", "--rename", "  La Cabra  "])
    check r.problem.len == 0 and r.edit and r.name == "Morro La Cabra (1/3)" and r.rename == "La Cabra"
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

suite "climbs: retiring":
  test "retire and unretire go with --edit; --retired and --duplicates are lists":
    check parseArgs(@["--edit", "X (2/3)", "--retire"]).retire
    check parseArgs(@["--edit", "X (2/3)", "--unretire"]).unretire
    check parseArgs(@["--retired"]).retired and parseArgs(@["--retired"]).listOnly
    check parseArgs(@["--duplicates"]).duplicates and parseArgs(@["--duplicates"]).listOnly
    check parseArgs(@["--retire"]).problem.contains("go with --edit")
    check parseArgs(@["--unretire"]).problem.contains("go with --edit")
    check parseArgs(@["--edit", "X", "--retire", "--unretire"]).problem.contains("cannot be used together")
    check parseArgs(@["--edit", "X", "--retire", "--rename", "Y"]).problem.contains("cannot be used together")
    check parseArgs(@["--edit", "X"]).problem.contains("--retire")
    check parseArgs(@["--retired", "--duplicates"]).problem.contains("cannot be used together")
    check parseArgs(@["--all", "--retired"]).problem.contains("cannot be used together")
    check parseArgs(@["--edit", "X", "--retire", "--retired"]).problem.contains("do not go with --edit")
    check parseArgs(@["--edit", "X", "--retire", "--all"]).problem.contains("do not go with --edit")


suite "climbs params: --delete":
  test "--delete needs --all, and -f goes with it":
    let c = parseArgs(@["--all", "--delete", "-f"])
    check c.problem == "" and c.delete and c.force
    check parseArgs(@["--delete"]).problem.contains("needs --all")
    check parseArgs(@["--all", "-f"]).problem.contains("goes with --delete")
    check parseArgs(@["--all", "--delete", "--retired"]).problem.len > 0
    check parseArgs(@["--all", "--delete", "--edit", "X", "--retire"]).problem.len > 0

suite "climbs params: --name, -v, --everyone":
  test "names, and the flags":
    let c = parseArgs(@["--name", "farellones", "cuesta", "-v", "--everyone"])
    check c.problem == "" and c.names == @["farellones", "cuesta"] and c.verbose and c.everyone
  test "--name needs text and goes with nothing that lists or changes":
    check parseArgs(@["--name"]).problem.len > 0
    for o in [@["--all"], @["--retired"], @["--duplicates"], @["--delete", "--all"], @["--edit", "X", "--retire"]]:
      check parseArgs(@["--name", "x"] & o).problem.len > 0
  test "-v and --everyone go with the attempts only":
    for o in [@["--all"], @["--retired"], @["--duplicates"], @["--edit", "X", "--retire"]]:
      check parseArgs(@["-v"] & o).problem.len > 0
      check parseArgs(@["--everyone"] & o).problem.len > 0
