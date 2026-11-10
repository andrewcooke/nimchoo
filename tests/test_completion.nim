## `nch --install-completion`, `--show-completion` and `nch __complete` (src/nimchoo/completion.nim): the shells, the script and where it goes.

import std/[options, os, strutils, unittest]
import nimchoo/completion
import nimchoo/core/[globals, manifest]

suite "nch --install-completion: the shell":
  test "bash is the one shell, and the default":
    check parseShell("bash") == some(shBash)
    check parseShell("") == some(defaultShell)
    check shellNames() == @["bash"]

  test "another shell is not one":
    check parseShell("zsh").isNone
    check parseShell("Bash").isNone

  test "every shell has a function":
    for s in Shell:
      check shellScript(s).len > 0

suite "nch --show-completion: the script":
  test "it calls the hidden command and says which status means files, as the program does":
    check "command \"${COMP_WORDS[0]}\" " & completeFlag in bashFunction
    check "-eq " & $exitFiles in bashFunction
    check "COMPLETE_FLAG" notin bashFunction and "EXIT_FILES" notin bashFunction

  test "it throws away what the command says on stderr, and runs the program as typed, not itself":
    check "2>/dev/null" in bashFunction
    check "command \"${COMP_WORDS[0]}\"" in bashFunction
    check "complete -F" in bashFunction

suite "nch --install-completion: writing the script":
  let dir = getTempDir() / "nch-test-completion"

  proc fresh(name: string): string =
    removeDir(dir)
    dir / name

  test "the script says whose it is, in its first line":
    check shellScript(shBash).splitLines()[0].startsWith(scriptMarker)

  test "it is written where it is asked for, with the directories above it":
    let path = fresh("a" / "b" / "nch")
    check install(shBash, path).isNone
    check readFile(path) == shellScript(shBash)

  test "an earlier script of ours is replaced":
    let path = fresh("nch")
    createDir(dir)
    writeFile(path, scriptMarker & " of an old version\nold text\n")
    check install(shBash, path).isNone
    check readFile(path) == shellScript(shBash)

  test "a file that is not ours is left alone, and the problem says why":
    let path = fresh("nch")
    createDir(dir)
    writeFile(path, "# somebody else's completion\n")
    let problem = install(shBash, path)
    check problem.isSome and "left alone" in problem.get
    check readFile(path) == "# somebody else's completion\n"

  test "a place that cannot be written is a problem, not a crash":
    let path = fresh("file" / "nch")
    createDir(dir)
    writeFile(dir / "file", "a file, where a directory should be")
    check install(shBash, path).isSome

  test "bash-completion's directory: its own variable, else the user's data directory":
    let had = getEnv("BASH_COMPLETION_USER_DIR")
    defer:
      if had.len > 0:
        putEnv("BASH_COMPLETION_USER_DIR", had)
      else:
        delEnv("BASH_COMPLETION_USER_DIR")
    putEnv("BASH_COMPLETION_USER_DIR", "/x/y")
    check scriptPath(shBash) == "/x/y/completions/nch"
    delEnv("BASH_COMPLETION_USER_DIR")
    check scriptPath(shBash) == getDataDir() / "bash-completion" / "completions" / "nch"

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
