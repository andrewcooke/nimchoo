## What the shell is offered (core/complete.nim): the commands, the options, the values of an option, from the
## descriptions of the options alone.

import std/[sequtils, unittest]
import nimchoo/core/[complete, globals, manifest, optdoc]
from nimchoo/registry import commands

func opt(
    names: openArray[string], arity = aFlag, completion = Completion(), level = 0
): OptDoc =
  OptDoc(names: @names, arity: arity, completion: completion, level: level)

proc headDocs(): seq[OptDoc] =
  @[
    opt(["--db"], aOne, Completion(kind: ckFile)),
    opt(["--user"], aOne, Completion(kind: ckDynamic, source: "user")),
    opt(["--offline"]),
    opt(["-h", "--help"]),
  ]

proc sizeDocs(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  @[
    opt(["-n", "--newest"], aOne),
    opt(["--kind"], aOne, Completion(kind: ckWords, words: @["big", "small", "bigger"])),
    opt(["--delete"], aList, Completion(kind: ckWords, words: @["all", "some"])),
    opt(["--profile"], aOne, Completion(kind: ckFile)),
    opt(["--force"]),
  ]

proc sizeCommands(): seq[CommandDecl] =
  @[
    CommandDecl(name: "size", options: sizeDocs),
    CommandDecl(name: "sort", options: sizeDocs),
    CommandDecl(name: "map", options: sizeDocs),
    CommandDecl(name: "undeclared"),
  ]

proc offered(line: varargs[string]): seq[string] =
  let o = complete(headDocs(), sizeCommands(), Globals(), @line)
  doAssert o.kind == okWords, "expected words"
  o.words

proc filesOffered(line: varargs[string]): bool =
  complete(headDocs(), sizeCommands(), Globals(), @line).kind == okFiles

suite "tab completion: commands and the options before them":
  test "nothing typed offers the commands, in order":
    check offered("") == @["map", "size", "sort", "undeclared"]

  test "the start of a command offers the commands that start so":
    check offered("s") == @["size", "sort"]
    check offered("x") == newSeq[string]()

  test "an option before the command offers the head options; the short ones only when asked for":
    check offered("--") == @["--db", "--user", "--offline", "--help"]
    check offered("-") == @["--db", "--user", "--offline", "-h", "--help"]
    check offered("--o") == @["--offline"]

  test "after head options the commands are offered again":
    check offered("--offline", "") == @["map", "size", "sort", "undeclared"]
    check offered("--user", "bob", "s") == @["size", "sort"]

  test "the value of a head option is not a command":
    check offered("--user", "") == newSeq[string]()
    check filesOffered("--db", "")
    check filesOffered("--offline", "--db", "x", "--db", "")

  test "an unknown option before the command, or an unknown command, offers nothing":
    check offered("--nope", "") == newSeq[string]()
    check offered("nope", "") == newSeq[string]()
    check offered("undeclared", "") == newSeq[string]()

suite "tab completion: the options of a command":
  test "an empty word after the command offers the long names, in the order they are declared":
    check offered("size", "") ==
      @["--newest", "--kind", "--delete", "--profile", "--force"]

  test "a single dash also offers the short names":
    check offered("size", "-") ==
      @["-n", "--newest", "--kind", "--delete", "--profile", "--force"]
    check offered("size", "--k") == @["--kind"]

  test "head options may come before the command":
    check offered("--db", "x.db", "--user", "bob", "size", "--f") == @["--force"]

  test "the value of an option is offered, by what the option says":
    check offered("size", "--kind", "") == @["big", "small", "bigger"]
    check offered("size", "--kind", "big") == @["big", "bigger"]
    check filesOffered("size", "--profile", "")
    check offered("size", "--newest", "") == newSeq[string]()

  test "a value that looks like an option is still the value":
    check offered("size", "--newest", "-5", "--f") == @["--force"]
    check offered("size", "--newest", "-") == newSeq[string]()

  test "a flag takes no value: the next word is an option or a positional":
    check offered("size", "--force", "--k") == @["--kind"]

  test "a list option offers its values until the next option, which ends it":
    check offered("size", "--delete", "") == @["all", "some"]
    check offered("size", "--delete", "all", "") == @["all", "some"]
    check offered("size", "--delete", "all", "-") ==
      @["-n", "--newest", "--kind", "--delete", "--profile", "--force"]
    check offered("size", "--delete", "all", "--force", "") ==
      @["--newest", "--kind", "--delete", "--profile", "--force"]

  test "bash breaks words at '=': `--kind=b` is `--kind`, `=`, `b`, and the `=` is not a word":
    check offered("size", "--kind", "=", "b") == @["big", "bigger"]
    check offered("size", "--kind", "=") == @["big", "small", "bigger"]
    check filesOffered("size", "--profile", "=")

  test "a command that declares no options offers nothing":
    check offered("undeclared", "--") == newSeq[string]()

  test "no words offers nothing":
    check complete(headDocs(), sizeCommands(), Globals(), @[]).words.len == 0

suite "tab completion: the real commands":
  test "every command of every package says what its options are":
    for c in commands:
      check not c.options.isNil

  test "every option the commands describe has a name, and a value placeholder when it takes one":
    for c in commands:
      for d in c.options(Globals()):
        check d.names.len > 0
        check (d.arity == aFlag) == (d.metavar.len == 0)

  test "the commands offered are those of the registry":
    let o = complete(headDocs(), commands, Globals(), @[""])
    check o.kind == okWords
    check commands.mapIt(it.name).allIt(it in o.words)
