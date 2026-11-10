## `nch --completion` and `nch __complete` (src/nimchoo/completion.nim): the shells, and the function the shell is given.

import std/[options, strutils, unittest]
import nimchoo/completion
import nimchoo/core/[globals, manifest]

suite "nch --completion: the shell":
  test "bash is the one shell, and the default":
    check parseShell("bash") == some(shBash)
    check parseShell("") == some(defaultShell)
    check shellNames() == @["bash"]

  test "another shell is not one":
    check parseShell("zsh").isNone
    check parseShell("Bash").isNone

  test "every shell has a function":
    for s in Shell:
      check shellFunction(s).len > 0

suite "nch --completion: the function":
  test "it calls the hidden command and says which status means files, as the program does":
    check "command \"${COMP_WORDS[0]}\" " & completeFlag in bashFunction
    check "-eq " & $exitFiles in bashFunction
    check "COMPLETE_FLAG" notin bashFunction and "EXIT_FILES" notin bashFunction

  test "it throws away what the command says on stderr, and runs the program as typed, not itself":
    check "2>/dev/null" in bashFunction
    check "command \"${COMP_WORDS[0]}\"" in bashFunction
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
