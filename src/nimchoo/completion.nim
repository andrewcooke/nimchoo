## Tab completion for the shell: `nch completion bash` prints the function that bash calls, and `nch __complete WORDS...`
## (hidden from the usage: only the shell runs it) answers it.  Like `nch packages` it is built into `nch` and not a
## package, because it needs the whole registry.  What is offered, and why, is `core/complete.nim`; this is the command
## line, the protocol with the shell and the function.
##
## **The protocol**: `__complete` is given the words after `nch`, up to and including the one being typed (empty if the
## cursor follows a space), and prints the candidates, one to a line, exiting 0.  If the value being typed is a file it
## prints nothing and exits `exitFiles`: the shell offers file names itself.  It never says anything on stderr and never
## fails: the tab key must not break the command line being typed.

import std/[options, strformat, strutils]
import ./core/[complete, globals, manifest]
import ./packages/ui/live
import ./packages/util/args/[args, usage]

{.push raises: [].}

const
  completeFlag* = "__complete" ## the word after `nch` that asks for completions
  exitFiles* = 10 ## `__complete`'s answer when the shell should offer file names

  bashTemplate = """_nch_complete() {
    local out rc line cur=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=()
    out=$(command nch COMPLETE_FLAG "${COMP_WORDS[@]:1:COMP_CWORD}" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq EXIT_FILES ]; then
        [ "$cur" = "=" ] && cur=
        compopt -o filenames 2>/dev/null
        while IFS= read -r line; do COMPREPLY+=("$line"); done < <(compgen -f -- "$cur")
    elif [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        while IFS= read -r line; do COMPREPLY+=("$line"); done <<<"$out"
    fi
}
complete -F _nch_complete nch
"""
    ## the function, with the two facts it shares with this module written as words (`bashFunction` fills them in).
    ## Bash gives `--sport=cyc` as three words (`=` is a word break); `complete.nim` knows.  stderr is thrown away: a
    ## message there garbles the line being typed (the prompt is not redrawn).

  bashFunction* = bashTemplate.replace("COMPLETE_FLAG", completeFlag).replace(
      "EXIT_FILES", $exitFiles
    ) ## what `nch completion bash` prints

type
  Shell* = enum
    shBash

  Params* = object ## what `nch completion` is asked for
    shell*: Shell

  Raw = object ## what the options fill in
    help: bool
    shells: seq[string]

func completionSpec*(): Spec[Raw] =
  ## The options of `nch completion`, and the shell as its argument.
  Spec[Raw](
    opts: @[helpFlag(Raw)],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      p.shells.add arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.shells.len != 1:
    return problemWith[Params]("say which shell: bash")
  case raw.shells[0]
  of "bash":
    parsedOk(Params(shell: shBash))
  else:
    problemWith[Params](fmt"no completion for '{raw.shells[0]}' (only bash)")

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch completion bash`.
  parseCommand(args, completionSpec(), Raw(), finish)

const
  synopsis = "usage: nch completion bash"
  intro =
    """Print the shell function that completes `nch` commands, options and, where the option has a fixed set of values or
takes a file, those too.  Put `eval "$(nch completion bash)"` in ~/.bashrc, or save the output where bash reads completions
(~/.local/share/bash-completion/completions/nch)."""

proc usageText*(width: int): string =
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(completionSpec().docs, width).join("\n") & "\n"

proc completionOptions(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  completionSpec().docs

proc completionMain(g: Globals, args: seq[string]): int {.nimcall, raises: [].} =
  ## Entry point for `nch completion ARGS`.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    exitOk
  of pkProblem:
    usageError("nch completion", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    case parsed.params.shell
    of shBash:
      stdout.say bashFunction
      exitOk

const completionCommand* = CommandDecl(
  name: "completion",
  summary: "the function that makes the shell complete nch commands and options (bash)",
  run: completionMain,
  options: completionOptions,
)

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
