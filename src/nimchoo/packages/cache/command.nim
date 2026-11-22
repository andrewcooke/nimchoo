## `nch cache`: the files outside the database (downloads, files unpacked from the program, and the files commands
## make).  With no arguments it says what there is, by kind, and how big; `--delete KIND...` deletes.  All of it
## is fetched, unpacked or made again when needed, so deleting needs no -f.

import std/[options, strutils]
import ./cache
import ../../core/[globals, ruled]
import ../util/args/[args, usage]
import ../ui/[style, units]
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
  intro = @[
    ~"Without options, say what is in the cache directory, by kind, and how big.  The cache holds only what is made again when it is needed (so deleting it needs no `-f`, and nothing in the database changes)."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the kinds, wrapped to `width`.
  var kinds: seq[Line]
  for k in Kind:
    let pad = " ".repeat(10 - len($k))
    kinds.add ~"  `{k}`{pad}{kindHelp[k]}"
  usageOf(synopsis, width, intro, cacheSpec().docs, sections = @[("kinds", kinds)])

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch cache ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch cache", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch cache", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let dir = cacheDir()
  if dir.isNone:
    return failure(g, "nch cache", noCacheDir)
  if p.action == caShow:
    g.show(osOut, ~"the cache is in <file {dir.get}>")
    var cells: seq[seq[string]]
    for k in Kind:
      let u = useOf(dir.get, k)
      cells.add @[
        $k,
        (if u.count == 0: "-" else: count(u.count)),
        (if u.count == 0: "-" else: humanBytes(u.bytes)),
      ]
    g.showAll(
      osOut,
      ruled(@["kind", "files", "size"], cells, g.textWidth(osOut), right = {1, 2}),
    )
    return exitOk
  var what: seq[string]
  for k in p.kinds:
    let u = deleteKind(dir.get, k)
    what.add $k & ": " & describe(u)
  let text = what.join("; ")
  g.log.log(lvInfo, commandName, leDeleted, text & " from " & dir.get)
  sayDeleted(g, "deleted " & text)
  exitOk
