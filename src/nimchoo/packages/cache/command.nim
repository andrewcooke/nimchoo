## `nch cache`: the files outside the database (downloads, files unpacked from the program, and the files commands
## make).  With no arguments it says what there is, by kind, and how big; `--delete KIND...` deletes.  All of it
## is fetched, unpacked or made again when needed, so deleting needs no -f.

import std/[options, strutils]
import ./cache
import ../../core/globals
import ../util/args/[args, usage]
import ../ui/[live, units]
import ../../core/logfile
import ../confirm/confirm
import ./[files, params]

{.push raises: [].}

const commandName* = "cache" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch cache`, described (for tab completion).
  cacheSpec().docs

const
  synopsis = """usage: nch cache
       nch cache --delete KIND..."""
  intro =
    """Without options, say what is in the cache directory, by kind, and how big.  The cache holds only what is made
again when it is needed (so deleting it needs no -f, and nothing in the database changes)."""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction, the options and the kinds, wrapped to `width`.
  result =
    synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(cacheSpec().docs, width).join("\n") & "\n\nThe kinds:\n"
  for k in Kind:
    result.add "  " & alignLeft($k, 10) & kindHelp[k] & "\n"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch cache ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch cache", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  let dir = cacheDir()
  if dir.isNone:
    return failure(
      "nch cache", "there is no cache directory (set NCH_CACHE, XDG_CACHE_HOME or HOME)"
    )
  if p.action == caShow:
    stdout.say "the cache is in " & dir.get & "\n"
    var cells: seq[array[3, string]]
    for k in Kind:
      let u = useOf(dir.get, k)
      cells.add [
        $k,
        (if u.count == 0: "-" else: insertSep($u.count, ',')),
        (if u.count == 0: "-" else: humanBytes(u.bytes)),
      ]
    for c in cells:
      stdout.say alignLeft(c[0], 10) & align(c[1], 8) & "  " & align(c[2], 10) & "\n"
    return exitOk
  var what: seq[string]
  for k in p.kinds:
    let u = deleteKind(dir.get, k)
    what.add $k & ": " & describe(u)
  let text = what.join("; ")
  g.log.log(lvInfo, commandName, leDeleted, text & " from " & dir.get)
  sayDeleted("deleted " & text)
  exitOk
