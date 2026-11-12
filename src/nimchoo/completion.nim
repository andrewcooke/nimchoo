## Tab completion for the shell: `nch --install-completion [SHELL]` writes the completion script where the shell finds it,
## `nch --show-completion [SHELL]` prints it (bash for now), and `nch __complete WORDS...` (hidden from the usage: only the shell runs it) answers it.  Like `nch packages` it is built
## into `nch` and not a package, because it needs the whole registry.  What is offered, and why, is `core/complete.nim`;
## this is the protocol with the shell and the functions.
##
## **The protocol**: `__complete` is given the words after `nch`, up to and including the one being typed (empty if the
## cursor follows a space), and prints the candidates, one to a line, exiting 0.  If the value being typed is a file it
## prints nothing and exits `exitFiles`: the shell offers file names itself.  It never says anything on stderr and never
## fails: the tab key must not break the command line being typed.

import std/[options, os, strformat, strutils]
import ./core/[complete, globals, manifest]
import ./packages/util/atomic/atomic

{.push raises: [].}

const
  completeFlag* = "__complete" ## the word after `nch` that asks for completions
  exitFiles* = 10 ## `__complete`'s answer when the shell should offer file names

  scriptMarker* = "# nch completion script"
    ## the first words of the script: `install` overwrites a file that starts so (it is ours), and no other

  bashTemplate =
    scriptMarker &
    """ (`nch --install-completion` writes it; it is overwritten each time)
_nch_unquote() {
    local w=$1 c i q=
    REPLY=
    for ((i = 0; i < ${#w}; i++)); do
        c=${w:i:1}
        if [ "$q" = "'" ]; then
            if [ "$c" = "'" ]; then q=; else REPLY+=$c; fi
        elif [ "$c" = '\' ]; then
            i=$((i + 1))
            c=${w:i:1}
            # (inside double quotes a backslash only escapes $ " ` and itself)
            if [ "$q" = '"' ] && [[ $c != [\$\"\`\\] ]]; then REPLY+='\'; fi
            REPLY+=$c
        elif [ -n "$q" ]; then
            if [ "$c" = "$q" ]; then q=; else REPLY+=$c; fi
        elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
            q=$c
        else
            REPLY+=$c
        fi
    done
}
_nch_complete() {
    local out rc line q i cur=${COMP_WORDS[COMP_CWORD]}
    local -a words=()
    COMPREPLY=()
    for ((i = 1; i <= COMP_CWORD; i++)); do
        _nch_unquote "${COMP_WORDS[i]}"
        words+=("$REPLY")
    done
    out=$(command "${COMP_WORDS[0]}" COMPLETE_FLAG "${words[@]}" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq EXIT_FILES ]; then
        [ "$cur" = "=" ] && cur=
        compopt -o filenames 2>/dev/null
        while IFS= read -r line; do COMPREPLY+=("$line"); done < <(compgen -f -- "$cur")
    elif [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        while IFS= read -r line; do
            printf -v q '%q' "$line"
            COMPREPLY+=("$q")
        done <<<"$out"
    fi
}
complete -F _nch_complete nch
"""
    ## the function, with the two facts it shares with this module written as words (`bashFunction` fills them in).  It
    ## runs the program as it was typed (`./nch` completes against that build, not whichever `nch` is on the path).
    ## Bash gives `--sports=cyc` as three words (`=` is a word break); `complete.nim` knows.  stderr is thrown away: a
    ## message there garbles the line being typed (the prompt is not redrawn).  The words typed are unquoted (a leading quote
    ## goes, and backslashes) before `__complete` sees them, and each candidate is quoted (`%q`), so a name with spaces is one
    ## word on the command line.  `nch` offers what starts with the word whatever the case and
    ## accents; bash replaces the word typed with the candidate (`f` becomes `Farellones`).

  bashFunction* = bashTemplate.replace("COMPLETE_FLAG", completeFlag).replace(
      "EXIT_FILES", $exitFiles
    )
    ## what `nch --show-completion` prints for bash, and `nch --install-completion` writes

type Shell* = enum
  ## The shells there is a completion script for (`nch --install-completion [SHELL]`); the name is the word typed.
  shBash = "bash"

const defaultShell* = shBash
  ## what `--install-completion` and `--show-completion` mean with no shell

func shellNames*(): seq[string] =
  ## The names of the shells, for the usage and for completing the option itself.
  for s in Shell:
    result.add $s

func parseShell*(word: string): Option[Shell] =
  ## The shell a word names ("": the default).
  if word.len == 0:
    return some(defaultShell)
  for s in Shell:
    if $s == word:
      return some(s)

type
  Action* = enum
    acInstall ## write the script where the shell finds it
    acShow ## print it

  Job* = object ## what `--install-completion` or `--show-completion` asks for
    action*: Action
    shell*: Shell

func shellScript*(s: Shell): string =
  ## The text the shell runs: the function, and its registration.
  case s
  of shBash: bashFunction

proc completeMain*(
    head: seq[OptDoc], commands: seq[CommandDecl], g: Globals, line: seq[string]
): int {.raises: [].} =
  ## Entry point for `nch __complete WORDS...`: the candidates for the last word, on stdout.
  let offer = complete(head, commands, g, line)
  case offer.kind
  of okFiles:
    exitFiles
  of okWords:
    if offer.words.len > 0:
      stdout.say offer.words.join("\n") & "\n"
    exitOk

proc scriptPath*(s: Shell): string =
  ## Where the shell finds the script of a command called `nch`, without being told: for bash, the user's directory of
  ## bash-completion (`$BASH_COMPLETION_USER_DIR`, else `$XDG_DATA_HOME`, else `~/.local/share`, then `bash-completion`),
  ## where a file named for a command is read the first time tab is pressed after it.
  case s
  of shBash:
    let base = getEnv("BASH_COMPLETION_USER_DIR", getDataDir() / "bash-completion")
    base / "completions" / "nch"

proc install*(s: Shell, path: string): Option[string] =
  ## Write the script of `s` at `path` (and the directories above it), over what is there if that is an earlier script of
  ## ours.  Returns what went wrong, as a sentence, if anything did: a file there that is not ours is left alone.
  try:
    if fileExists(path):
      let first = readFile(path).splitLines()[0]
      if not first.startsWith(scriptMarker):
        return some(
          fmt"{path} exists and is not a completion script of nch's (it does not start with '{scriptMarker}'): it is left alone"
        )
    createDir(parentDir(path))
    writeAtomic(path, shellScript(s))
  except IOError, OSError:
    return some(fmt"cannot write {path}: {getCurrentExceptionMsg()}")

proc installMain*(s: Shell): int {.raises: [].} =
  ## `nch --install-completion [SHELL]`: write the script, and say where and what is left to do.
  let path = scriptPath(s)
  let problem = install(s, path)
  if problem.isSome:
    return failure("nch", problem.get)
  stdout.say fmt"wrote {path}: new {s} shells complete nch (this one: source {path})" &
    "\n"
  exitOk

proc showMain*(s: Shell): int {.raises: [].} =
  ## `nch --show-completion [SHELL]`: print the script.
  stdout.say shellScript(s)
  exitOk
