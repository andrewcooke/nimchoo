import std/[options, strutils, unittest]
import nimchoo/packages/user/params
import nimchoo/packages/util/args/args

suite "user: names and FTHR":
  test "names: 1 to 32 of letters, digits and _ . -, not starting with -":
    for ok in ["a", "bob", "Bob_2", "a.b-c", "x".repeat(32), "default", "1", "_x", ".x"]:
      check validUserName(ok)
    for bad in [
      "", "-x", "a b", "a,b", "a/b", "é", "a;b", "x".repeat(33), "a\n", "'", "\""
    ]:
      check not validUserName(bad)
  test "FTHR: a whole number of bpm, 80 to 230":
    check parseFthr("154") == some(154)
    check parseFthr("80") == some(80) and parseFthr("230") == some(230)
    for bad in ["", "79", "231", "x", "1.5", "154 ", "-5", "1e2", "0"]:
      check parseFthr(bad).isNone

suite "user: the command line":
  test "no arguments: show the users":
    let p = parseArgs(@[])
    check p.params.action == uaList and p.problem == ""
  test "make a user, with or without an FTHR":
    let p = parseArgs(@["--add", "bob"])
    check p.params.action == uaAdd and p.params.add.name == "bob" and
      p.params.add.fthr.isNone
    let q = parseArgs(@["--add", "bob", "--fthr", "150"])
    check q.problem == "" and q.params.add.name == "bob" and
      q.params.add.fthr == some(150)
  test "edit: set, clear, rename, make the default":
    let p = parseArgs(@["--edit", "bob", "--fthr", "154"])
    check p.problem == "" and p.params.action == uaEdit and p.params.edit.name == "bob"
    check p.params.edit.fthr.kind == fkSet and p.params.edit.fthr.bpm == 154
    check parseArgs(@["--edit", "bob", "--clear-fthr"]).params.edit.fthr.kind == fkClear
    check parseArgs(@["--edit", "bob", "--rename", "robert"]).params.edit.rename ==
      some("robert")
    check parseArgs(@["--edit", "bob", "--default"]).params.edit.makeDefault
    check parseArgs(@["--edit", "bob", "--default"]).params.edit.fthr.kind == fkKeep
    let q = parseArgs(@["--edit", "bob", "--fthr", "150", "--rename", "x"])
      # several at once are fine
    check q.params.edit.fthr.bpm == 150 and q.params.edit.rename == some("x") and
      q.problem == ""
  test "a bare name is not taken for a user, and the message says what to do":
    let p = parseArgs(@["bob", "--fthr", "150"])
    check p.problem.contains("unexpected argument bob") and
      p.problem.contains("--add bob") and p.problem.contains("--edit bob")
  test "the changes go with --add or --edit":
    check parseArgs(@["--fthr", "154"]).problem.contains(
      "go with --add NAME or --edit NAME"
    )
    check parseArgs(@["--default"]).problem.contains(
      "go with --add NAME or --edit NAME"
    )
    check parseArgs(@["--rename", "x"]).problem.contains(
      "go with --add NAME or --edit NAME"
    )
    check parseArgs(@["--edit", "bob"]).problem.contains("needs something to change")
  test "--default, alone with --edit or with --add":
    let p = parseArgs(@["--add", "bob", "--default"])
    check p.problem == "" and p.params.action == uaAdd and p.params.add.makeDefault
  test "only one of --add, --edit and --delete":
    check parseArgs(@["--add", "a", "--edit", "b", "--fthr", "150"]).problem.contains(
      "cannot be used together"
    )
  test "problems":
    check parseArgs(@["--add"]).problem.contains("--add needs a value")
    check parseArgs(@["--edit"]).problem.contains("--edit needs a value")
    check parseArgs(@["--add", "bad name"]).problem.contains("not a name for a user")
    check parseArgs(@["--add", "-x"]).problem.contains("not a name for a user")
    check parseArgs(@["--add", "a", "b"]).problem.contains("unexpected argument b")
    check parseArgs(@["--add", "bob", "--rename", "x"]).problem.contains(
      "only with --fthr"
    )
    check parseArgs(@["--add", "bob", "--clear-fthr"]).problem.contains(
      "only with --fthr"
    )
    check parseArgs(@["--edit", "bob", "--fthr", "150", "--clear-fthr"]).problem
      .contains("cannot be used together")
    check parseArgs(@["--edit", "bob", "--fthr"]).problem.contains("needs a value")
    check parseArgs(@["--edit", "bob", "--fthr", "79"]).problem.contains("80 to 230")
    check parseArgs(@["--edit", "bob", "--fthr", "abc"]).problem.contains("'abc'")
    check parseArgs(@["--edit", "bob", "--rename"]).problem.contains("needs a value")
    check parseArgs(@["--edit", "bob", "--rename", "-x"]).problem.contains("not a name")
    check parseArgs(@["--edit", "bob", "--rename", "a b"]).problem.contains(
      "not a name"
    )
  test "help":
    check parseArgs(@["-h"]).help and parseArgs(@["--help"]).help
    check parseArgs(@["--add", "bob", "-h"]).problem == "" # (help wins over the rest)

suite "user params: --delete":
  test "--delete NAME, with -f":
    let p = parseArgs(@["--delete", "bob", "-f"])
    check p.problem == "" and p.params.action == uaDelete and
      p.params.delete.name == "bob" and p.params.delete.force
    check parseArgs(@["--delete", "bob"]).params.delete.force == false
    check parseArgs(@["--delete"]).problem.contains("needs a value")
  test "--delete stands alone, and -f goes with it":
    check parseArgs(@["--delete", "bob", "--fthr", "150", "-f"]).problem.contains(
      "cannot be combined"
    )
    check parseArgs(@["--delete", "bob", "--rename", "x"]).problem.contains(
      "cannot be combined"
    )
    check parseArgs(@["-f"]).problem.contains("goes with --delete")
    check parseArgs(@["--add", "bob", "-f"]).problem.contains("goes with --delete")
