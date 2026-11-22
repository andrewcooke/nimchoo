import std/[strutils, unittest]
import nimchoo/packages/names/params
import nimchoo/packages/util/args/args

suite "landmark: the command line":
  test "no arguments lists":
    let p = parseArgs(@[])
    check p.params.action == laList and p.problem.len == 0
  test "searches and suggestions":
    let s = parseArgs(@["--search", "yerba"]).params
    check s.action == laSearch and s.suggest.kind == skSearch and
      s.suggest.text == "yerba"
    let n = parseArgs(@["--near", "-33.344,-70.364"]).params
    check n.action == laNear and n.suggest.kind == skNear
    check abs(n.suggest.near.lon + 70.364) < 1e-9 and
      abs(n.suggest.near.lat + 33.344) < 1e-9
  test "adding from a suggestion, or at a position":
    let a = parseArgs(
      @["--add", "Yerba Loca", "--search", "yerba", "--pick", "2", "--size", "1500m"]
    )
    check a.problem.len == 0 and a.params.action == laAddPicked
    check a.params.picked.name == "Yerba Loca" and a.params.picked.pick == 2 and
      a.params.picked.radiusM == 1500.0 and a.params.picked.suggestions.kind == skSearch
    let b = parseArgs(@["--add", "Casa", "--at", "-33.4,-70.6"])
    check b.problem.len == 0 and b.params.action == laAddAt and
      b.params.placed.radiusM == 1000.0
    let c = parseArgs(@["--add", "Calán", "--near", "-33.4,-70.6", "--pick", "1"])
    check c.problem.len == 0 and c.params.action == laAddPicked and
      c.params.picked.suggestions.kind == skNear and c.params.picked.pick == 1
  test "removing":
    let r = parseArgs(@["--delete", "Casa"])
    check r.problem.len == 0 and r.params.action == laDelete and
      r.params.deleted.name == "Casa" and not r.params.deleted.force
  test "the size has its unit: m or km; with none it is the question, m added":
    check parseArgs(@["--add", "X", "--at", "1,2", "--size", "1.5km"]).params.placed.radiusM ==
      1500.0
    let q = parseArgs(@["--add", "X", "--at", "1,2", "--size", "800"])
    check q.kind == pkUnit and
      q.fix.args == @["--add", "X", "--at", "1,2", "--size", "800m"]
    for bad in ["0m", "-5m", "nanm", "5mi", "x"]:
      check parseArgs(@["--add", "X", "--at", "1,2", "--size", bad]).problem.contains(
        "--size"
      )
  test "mistakes":
    check parseArgs(@["--add", "X"]).problem.contains("needs one of")
    check parseArgs(@["--add", "X", "--search", "y"]).problem.contains("--pick")
    check parseArgs(@["--add", "X", "--at", "1,2", "--pick", "1"]).problem.contains(
      "not with `--at`"
    )
    check parseArgs(@["--add", "X", "--search", "y", "--near", "1,2", "--pick", "1"]).problem
      .contains("needs one of")
    check parseArgs(@["--add", "", "--at", "1,2"]).problem.contains("needs a name")
    check parseArgs(@["--add", "X", "--at", "1,2", "--size", "5m"]).problem.contains(
      "radius"
    )
    check parseArgs(@["--add", "X", "--at", "1,2", "--size", "99999m"]).problem.contains(
      "radius"
    )
    check parseArgs(@["--add", "X", "--at", "200,1"]).problem.contains("LAT,LON")
    check parseArgs(@["--at", "1,2"]).problem.contains("--add")
    check parseArgs(@["--pick", "1"]).problem.contains("--add")
    check parseArgs(@["--pick", "0"]).problem.contains("from 1")
    check parseArgs(@["--delete", "X", "--add", "Y"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--delete", "X", "--search", "y"]).problem.contains("name only")
    check parseArgs(@["--search", "a", "--near", "1,2"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--size", "500m"]).problem.contains("--add")
    check parseArgs(@["Yerba"]).problem.contains("`--search Yerba`")
