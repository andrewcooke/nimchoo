## `nch --install-completion`, `--show-completion` and `nch __complete` (src/nimchoo/completion.nim): the shells, the script and where it goes.

import std/[options, os, osproc, strutils, unittest]
import ./support/env
import nimchoo/completion
import nimchoo/core/[globals, manifest, optdoc]
import nimchoo/packages/user/session
from nimchoo/registry import allAccess, allFragments, commands, extensions

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

suite "nch __complete: it changes nothing":
  teardown:
    useTestCache()
  test "every option's values, for every command, make no cache file and leave the database as it was":
    let top = getTempDir() / "nch-test-complete"
    removeDir top
    createDir top
    let cache = top / "cache"
    putEnv("NCH_CACHE", cache)
    let db = top / "x.db"
    openSession(db, allFragments, access = allAccess).close()
    let before = readFile(db)
    let g = Globals(
      dbPath: db,
      fragments: allFragments,
      access: allAccess,
      extensions: extensions,
      offline: true,
      readOnly: true,
    )
    var asked = 0
    for c in commands:
      for o in c.options(g):
        if o.arity == aOne:
          discard completeMain(@[], commands, g, @[c.name, o.names[^1], ""])
          inc asked
    check asked > 20 # (the providers of the whole program were asked)
    check not dirExists(cache) # (no cache file, not even the directory)
    check readFile(db) == before

suite "nch __complete: the bash function with awkward names":
  # (run in a real bash, against a stub that answers with these names and records the last word it was given)
  const names = [
    "Cerro San Luis₄", "it's", "say \"hi\"", "a\\b", "$HOME", "a;b", "a&b", "(x)",
    "*", "?x", "[a]", "{a,b}", "#c", "!h", "~u", "a|b", "<a>", "é", "a  b", "x=y",
    "`ls`", "$(ls)", "back\\", "'", "\"",
  ]
  test "each candidate is one word that reads back as itself, and as typed it is read as itself":
    let top = getTempDir() / "nch-test-bash"
    removeDir top
    createDir top
    writeFile(top / "names", names.join("\n") & "\n")
    writeFile(
      top / "stub",
      "#!/bin/bash\nprintf '%s' \"${@: -1}\" > " & top / "last" & "\ncat " &
        top / "names\n",
    )
    setFilePermissions(top / "stub", {fpUserRead, fpUserWrite, fpUserExec})
    writeFile(top / "fn.sh", bashFunction)
    writeFile(
      top / "run.sh",
      "source " & top / "fn.sh" & "\n" &
        """
mapfile -t names < NAMES
stub=STUB
COMP_WORDS=("$stub" ""); COMP_CWORD=1
_nch_complete
[ ${#COMPREPLY[@]} -eq ${#names[@]} ] || echo "count ${#COMPREPLY[@]}"
for i in "${!names[@]}"; do
  eval "set -- ${COMPREPLY[i]}"
  [ $# -eq 1 ] && [ "$1" = "${names[i]}" ] || echo "candidate ${names[i]}: ${COMPREPLY[i]}"
done
for n in "${names[@]}"; do
  printf -v q '%q' "$n"
  COMP_WORDS=("$stub" "$q"); COMP_CWORD=1
  _nch_complete
  [ "$(cat LAST)" = "$n" ] || echo "typed ${n}: got $(cat LAST)"
done
typed=("'a b'" '"a b"' '"a\"b"' 'a\ b' '"a\\b"' '"a\xb"' "a'b c'd")
want=("a b" "a b" 'a"b' "a b" 'a\b' 'a\xb' "ab cd")
for i in "${!typed[@]}"; do
  COMP_WORDS=("$stub" "${typed[i]}"); COMP_CWORD=1
  _nch_complete
  [ "$(cat LAST)" = "${want[i]}" ] || echo "typed ${typed[i]}: got $(cat LAST), wanted ${want[i]}"
done
"""
        .replace("NAMES", top / "names")
        .replace("STUB", top / "stub")
        .replace("LAST", top / "last"),
    )
    let (output, code) = execCmdEx("bash " & top / "run.sh")
    check output == ""
    check code == 0
