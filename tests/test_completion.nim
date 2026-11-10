## `nch completion` and `nch __complete` (src/nimchoo/completion.nim): the command line and the function bash is given.

import std/[strutils, unittest]
import nimchoo/completion
import nimchoo/core/[globals, manifest]
import nimchoo/packages/util/args/args

suite "nch completion: the command line":
  test "bash is the one shell":
    let p = parseArgs(@["bash"])
    check p.problem == "" and p.params.shell == shBash

  test "no shell, two shells or another shell is a problem":
    check parseArgs(@[]).problem.len > 0
    check parseArgs(@["bash", "bash"]).problem.len > 0
    check "zsh" in parseArgs(@["zsh"]).problem

  test "help is asked for":
    check parseArgs(@["--help"]).help

suite "nch completion: the function":
  test "it calls the hidden command and says which status means files, as the program does":
    check "command nch " & completeFlag in bashFunction
    check "-eq " & $exitFiles in bashFunction
    check "COMPLETE_FLAG" notin bashFunction and "EXIT_FILES" notin bashFunction

  test "it throws away what the command says on stderr, and cannot call itself":
    check "2>/dev/null" in bashFunction
    check "command nch" in bashFunction
    check "complete -F" in bashFunction

suite "nch __complete":
  test "the exit status is 0 for candidates, and the files status for a file":
    let head = @[
      OptDoc(
        names: @["--db"],
        metavar: "PATH",
        arity: aOne,
        completion: Completion(kind: ckFile),
      )
    ]
    check completeMain(head, @[], Globals(), @["--db", ""]) == exitFiles
    check completeMain(head, @[], Globals(), @[]) == exitOk
