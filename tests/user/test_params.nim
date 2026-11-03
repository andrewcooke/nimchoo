import std/[options, strutils, unittest]
import nimchoo/user/params

suite "user: names and FTHR":
  test "names: 1 to 32 of letters, digits and _ . -, not starting with -":
    for ok in ["a", "bob", "Bob_2", "a.b-c", "x".repeat(32), "default", "1", "_x", ".x"]:
      check validUserName(ok)
    for bad in ["", "-x", "a b", "a,b", "a/b", "é", "a;b", "x".repeat(33), "a\n", "'", "\""]:
      check not validUserName(bad)
  test "FTHR: a whole number of bpm, 80 to 230":
    check parseFthr("154") == some(154)
    check parseFthr("80") == some(80) and parseFthr("230") == some(230)
    for bad in ["", "79", "231", "x", "1.5", "154 ", "-5", "1e2", "0"]:
      check parseFthr(bad).isNone

suite "user: the command line":
  test "no arguments: show the users":
    let p = parseArgs(@[])
    check p.list and p.problem == ""
  test "make a user, with or without an FTHR":
    let p = parseArgs(@["--create", "bob"])
    check p.create and p.name == "bob" and p.fthr.isNone and not p.list
    let q = parseArgs(@["--create", "bob", "--fthr", "150"])
    check q.create and q.name == "bob" and q.fthr == some(150) and q.problem == ""
  test "set, clear, rename":
    check parseArgs(@["--fthr", "154"]).fthr == some(154)
    check parseArgs(@["--fthr", "154"]).problem == ""
    check parseArgs(@["--clear-fthr"]).clearFthr
    check parseArgs(@["--rename", "robert"]).rename == "robert"
    let p = parseArgs(@["--fthr", "150", "--rename", "x"])          # several at once are fine
    check p.fthr == some(150) and p.rename == "x" and p.problem == "" and not p.list
  test "a bare name is not taken to mean the current user, and the message says what to do":
    let p = parseArgs(@["bob", "--fthr", "150"])
    check p.problem.contains("unexpected argument bob") and p.problem.contains("--create bob") and
      p.problem.contains("--user bob")
  test "--default, alone or with --create":
    check parseArgs(@["--default"]).makeDefault and not parseArgs(@["--default"]).list
    let p = parseArgs(@["--create", "bob", "--default"])
    check p.makeDefault and p.create and p.problem == ""
  test "problems":
    check parseArgs(@["--create"]).problem.contains("--create needs a value")
    check parseArgs(@["--create", "bad name"]).problem.contains("not a name for a user")
    check parseArgs(@["--create", "-x"]).problem.contains("not a name for a user")
    check parseArgs(@["--create", "a", "b"]).problem.contains("unexpected argument b")
    check parseArgs(@["--create", "bob", "--rename", "x"]).problem.contains("only with --fthr")
    check parseArgs(@["--create", "bob", "--clear-fthr"]).problem.contains("only with --fthr")
    check parseArgs(@["--fthr", "150", "--clear-fthr"]).problem.contains("cannot be used together")
    check parseArgs(@["--fthr"]).problem.contains("needs a value")
    check parseArgs(@["--fthr", "79"]).problem.contains("80 to 230")
    check parseArgs(@["--fthr", "abc"]).problem.contains("'abc'")
    check parseArgs(@["--rename"]).problem.contains("needs a value")
    check parseArgs(@["--rename", "-x"]).problem.contains("not a name")
    check parseArgs(@["--rename", "a b"]).problem.contains("not a name")
  test "help":
    check parseArgs(@["-h"]).help and parseArgs(@["--help"]).help
    check parseArgs(@["--create", "bob", "-h"]).problem == ""                  # (help wins over the rest)
