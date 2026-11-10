import std/[strutils, unittest]
import nimchoo/packages/climbs/params
import nimchoo/packages/util/args/args

suite "climbs: the command line":
  test "no arguments: the climbs of the selected activities; --all: every climb":
    let p = parseArgs(@[])
    check p.problem.len == 0 and p.params.action == caSelected
    let a = parseArgs(@["--all"])
    check a.problem.len == 0 and a.params.action == caAll
  test "rename and auto":
    let r = parseArgs(@["--edit", "Morro La Cabra₁", "--rename", "  La Cabra  "])
    check r.problem.len == 0 and r.params.action == caEdit and
      r.params.edit.climb == "Morro La Cabra₁"
    check r.params.edit.change.kind == ckRename and
      r.params.edit.change.newName == "La Cabra"
    let a = parseArgs(@["--edit", "X", "--auto"])
    check a.problem.len == 0 and a.params.edit.change.kind == ckAuto
  test "mistakes":
    check parseArgs(@["--edit", "X"]).problem.contains("something to change")
    check parseArgs(@["--edit", "X", "--rename", "Y", "--auto"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--rename", "Y"]).problem.contains("go with --edit")
    check parseArgs(@["--auto"]).problem.contains("go with --edit")
    check parseArgs(@["--edit", " ", "--auto"]).problem.contains("needs the name")
    check parseArgs(@["Cerro"]).problem.contains("--edit Cerro --rename NEW")
  test "names that are refused":
    check nameProblem("Cerro Calán") == ""
    check nameProblem("  ").contains("empty")
    check nameProblem("x".repeat(61)).contains("at most")
    check nameProblem("a\nb").contains("control")
    check nameProblem("Cuesta₂").contains("subscript")
    check nameProblem("Cuesta (the 2/3 one)") == ""
    check parseArgs(@["--edit", "X", "--rename", "Cuesta₂"]).problem.contains(
      "subscript"
    )
  test "an old-style (n/m) at the end is just text now":
    check nameProblem("Cuesta (2/3)") == ""

suite "climbs: retiring":
  test "retire and unretire go with --edit; --retired and --duplicates are lists":
    check parseArgs(@["--edit", "X₂", "--retire"]).params.edit.change.kind == ckRetire
    check parseArgs(@["--edit", "X₂", "--unretire"]).params.edit.change.kind ==
      ckUnretire
    check parseArgs(@["--retired"]).params.action == caRetired
    check parseArgs(@["--duplicates"]).params.action == caDuplicates
    check parseArgs(@["--retire"]).problem.contains("go with --edit")
    check parseArgs(@["--unretire"]).problem.contains("go with --edit")
    check parseArgs(@["--edit", "X", "--retire", "--unretire"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--edit", "X", "--retire", "--rename", "Y"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--edit", "X"]).problem.contains("--retire")
    check parseArgs(@["--retired", "--duplicates"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--all", "--retired"]).problem.contains("cannot be used together")
    check parseArgs(@["--edit", "X", "--retire", "--retired"]).problem.contains(
      "do not go with --edit"
    )
    check parseArgs(@["--edit", "X", "--retire", "--all"]).problem.contains(
      "do not go with --edit"
    )

suite "climbs params: --delete":
  test "--delete needs --all, and -f goes with it":
    let c = parseArgs(@["--all", "--delete", "-f"])
    check c.problem == "" and c.params.action == caDeleteAll and c.params.force
    check parseArgs(@["--delete"]).problem.contains("needs --all")
    check parseArgs(@["--all", "-f"]).problem.contains("goes with --delete")
    check parseArgs(@["--all", "--delete", "--retired"]).problem.len > 0
    check parseArgs(@["--all", "--delete", "--edit", "X", "--retire"]).problem.len > 0

suite "climbs params: --name, -v, --everyone":
  test "names, and the flags":
    let c = parseArgs(@["--name", "farellones", "cuesta", "-v", "--everyone"])
    check c.problem == "" and c.params.action == caNamed
    check c.params.named.names == @["farellones", "cuesta"] and
      c.params.named.attempts.verbose and c.params.named.attempts.everyone
  test "--name needs text and goes with nothing that lists or changes":
    check parseArgs(@["--name"]).problem.len > 0
    for o in [
      @["--all"],
      @["--retired"],
      @["--duplicates"],
      @["--delete", "--all"],
      @["--edit", "X", "--retire"],
    ]:
      check parseArgs(@["--name", "x"] & o).problem.len > 0
  test "-v and --everyone go with the attempts only":
    for o in [
      @["--all"], @["--retired"], @["--duplicates"], @["--edit", "X", "--retire"]
    ]:
      check parseArgs(@["-v"] & o).problem.len > 0
      check parseArgs(@["--everyone"] & o).problem.len > 0
