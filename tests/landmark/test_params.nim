import std/[options, strutils, unittest]
import nimchoo/landmark/params

suite "landmark: the command line":
  test "no arguments lists":
    let p = parseArgs(@[])
    check p.list and p.problem.len == 0
  test "searches and suggestions":
    check parseArgs(@["--search", "yerba"]).search == "yerba"
    check not parseArgs(@["--search", "yerba"]).list
    let n = parseArgs(@["--near", "-70.364,-33.344"])
    check n.near.isSome and abs(n.near.get.lon + 70.364) < 1e-9 and abs(n.near.get.lat + 33.344) < 1e-9
  test "adding from a suggestion, or at a position":
    let a = parseArgs(@["--add", "Yerba Loca", "--search", "yerba", "--pick", "2", "--radius", "1500"])
    check a.problem.len == 0 and a.add and a.name == "Yerba Loca" and a.pick == 2 and a.radiusM == 1500.0
    let b = parseArgs(@["--add", "Casa", "--at", "-70.6,-33.4"])
    check b.problem.len == 0 and b.add and b.at.isSome and b.radiusM == 1000.0
    let c = parseArgs(@["--add", "Calán", "--near", "-70.6,-33.4", "--pick", "1"])
    check c.problem.len == 0 and c.near.isSome and c.pick == 1
  test "removing":
    let r = parseArgs(@["--delete", "Casa"])
    check r.problem.len == 0 and r.delete and r.name == "Casa"
  test "mistakes":
    check parseArgs(@["--add", "X"]).problem.contains("needs one of")
    check parseArgs(@["--add", "X", "--search", "y"]).problem.contains("--pick")
    check parseArgs(@["--add", "X", "--at", "1,2", "--pick", "1"]).problem.contains("not with --at")
    check parseArgs(@["--add", "X", "--search", "y", "--near", "1,2", "--pick", "1"]).problem.contains("needs one of")
    check parseArgs(@["--add", "", "--at", "1,2"]).problem.contains("needs a name")
    check parseArgs(@["--add", "X", "--at", "1,2", "--radius", "5"]).problem.contains("radius")
    check parseArgs(@["--add", "X", "--at", "1,2", "--radius", "99999"]).problem.contains("radius")
    check parseArgs(@["--add", "X", "--at", "1,200"]).problem.contains("LON,LAT")
    check parseArgs(@["--at", "1,2"]).problem.contains("--add")
    check parseArgs(@["--pick", "1"]).problem.contains("--add")
    check parseArgs(@["--pick", "0"]).problem.contains("from 1")
    check parseArgs(@["--delete", "X", "--add", "Y"]).problem.contains("cannot be used together")
    check parseArgs(@["--delete", "X", "--search", "y"]).problem.contains("name only")
    check parseArgs(@["--search", "a", "--near", "1,2"]).problem.contains("cannot be used together")
    check parseArgs(@["--radius", "500"]).problem.contains("--add")
    check parseArgs(@["Yerba"]).problem.contains("--search Yerba")
  test "positions":
    check parsePosition("1.5,-2.5").get == (1.5, -2.5)
    check parsePosition(" -70.364 , -33.344 ").isSome
    check parsePosition("1").isNone and parsePosition("a,b").isNone and parsePosition("181,0").isNone and parsePosition("0,91").isNone
