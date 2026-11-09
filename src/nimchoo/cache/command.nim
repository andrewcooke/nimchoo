## `nch cache`: the files outside the database (downloads, files unpacked from the program, and the files commands
## make).  With no arguments it says what there is, by kind, and how big; `--delete KIND...` deletes.  All of it
## is fetched, unpacked or made again when needed, so deleting needs no -f.

import std/[options, strutils]
import ../cache
import ../cli/common
import ../packages/util/args/args
import ../download/fetch
import ../ui/logfile
import ../user/wipe
import ./files

{.push raises: [].}

const usage* = """usage: nch cache
       nch cache --delete KIND...

Without options, say what is in the cache directory, by kind, and how big.  The cache holds only what is made
again when it is needed (so deleting it needs no -f, and nothing in the database changes).

  --delete KIND...   delete the files of those kinds (or `all`)
  -h, --help         show this help

The kinds:
"""

type CacheArgs = object
  kinds: seq[Kind]
  delete, all, help: bool

proc takeKinds(
    p: var CacheArgs, name: string, values: seq[string]
): string {.nimcall.} =
  p.delete = true
  for v in values:
    var k: Kind
    if v.toLowerAscii == "all":
      p.all = true
    elif parseKind(v, k):
      if k notin p.kinds:
        p.kinds.add k
    else:
      return "no such kind of cache file: " & v & " (" & kindNames() & ", or all)"
  if values.len == 0:
    return name & " needs a kind: " & kindNames() & ", or all"
  ""

func fullUsage(): string =
  ## The help, with the kinds and what each is.
  result = usage
  for k in Kind:
    result.add "  " & alignLeft($k, 10) & kindHelp[k] & "\n"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch cache ARGS`; returns the exit status.
  var given = CacheArgs()
  let spec = Spec[CacheArgs](
    opts: @[
      flag(CacheArgs, ["-h", "--help"], help),
      listOption[CacheArgs](["--delete"], takeKinds),
    ]
  )
  let help = fullUsage()
  let why = parseOptions(args, spec, given)
  if why.len > 0:
    return usageError("nch cache", help, why)
  if given.help:
    stdout.say help
    return exitOk
  let dir = cacheDir()
  if dir.isNone:
    return failure(
      "nch cache", "there is no cache directory (set NCH_CACHE, XDG_CACHE_HOME or HOME)"
    )
  if not given.delete:
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
  let kinds =
    if given.all:
      @[ckDownloads, ckSystem, ckGeojson, ckCsv, ckHtml]
    else:
      given.kinds
  var what: seq[string]
  for k in kinds:
    let u = deleteKind(dir.get, k)
    what.add $k & ": " & describe(u)
  let text = what.join("; ")
  g.log.log(lvInfo, cmCache, leDeleted, text & " from " & dir.get)
  sayDeleted("deleted " & text)
  exitOk
