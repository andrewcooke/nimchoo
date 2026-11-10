## The command line of `nch cache`, parsed.  Pure.

import std/strutils
import ../util/args/args
import ./files

{.push raises: [].}

type
  CacheAction* = enum
    caShow ## say what is in the cache
    caDelete

  Params* = object
    case action*: CacheAction
    of caShow:
      discard
    of caDelete:
      kinds*: seq[Kind] ## what to delete (`all` is all of them)

  Raw = object ## what the options fill in
    help, delete, all: bool
    kinds: seq[Kind]

proc takeKinds(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  p.delete = true
  if values.len == 0:
    return refuse(name & " needs a kind: " & kindNames() & ", or all")
  for v in values:
    var k: Kind
    if v.toLowerAscii == "all":
      p.all = true
    elif parseKind(v, k):
      if k notin p.kinds:
        p.kinds.add k
    else:
      return
        refuse("no such kind of cache file: " & v & " (" & kindNames() & ", or all)")
  fine

func cacheSpec*(): Spec[Raw] =
  ## The options of `nch cache`.
  Spec[Raw](
    opts: @[
      listOption[Raw](
        ["--delete"],
        takeKinds,
        "KIND...",
        "delete the files of those kinds (or `all`)",
        completion = Completion(kind: ckWords, words: kindWords()),
      ),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  if not raw.delete:
    return parsedOk(Params(action: caShow))
  var kinds = raw.kinds
  if raw.all:
    kinds = @[]
    for k in Kind:
      kinds.add k
  parsedOk(Params(action: caDelete, kinds: kinds))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch cache`, `nch cache --delete KIND...`.
  parseCommand(args, cacheSpec(), Raw(), finish)
