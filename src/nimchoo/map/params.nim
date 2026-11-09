## The command line of `nch map`, parsed.  Pure.  There are only the two options that say what is drawn, and they are
## for programs: the address a page has carries them (`bits=...&check=...`), and the server hands them to the worker.

import std/sequtils
import ../packages/util/args/args
import ../packages/selection/bits
import ../packages/web/webopts

{.push raises: [].}

type Params* = object
  bits*: string
    ## the activities to draw, as in an address (selection/bits.nim); "": the current selection
  check*: string
    ## a short hash of the content of those activities, which they must still have ("": no check)
  web*: WebArgs ## --worker, --web and what goes with it
  help*: bool
  problem*: string ## "" if the command line was fine

proc parseArgs*(args: seq[string]): Params =
  ## `--bits STRING`, `--check HASH`, `--worker`, `--web` (with `--no-open`, `--port N`, `--new-token`), `-h`.
  result = Params(web: initWebArgs())
  let bitsOption = custom(Params, ["--bits"], true):
    if not isBitsString(value):
      return "'" & value & "' is not a list of activities"
    p.bits = value
    ""
  let checkOption = custom(Params, ["--check"], true):
    if value.len == 0 or value.len > 64 or
        not value.allIt(it in {'0' .. '9', 'a' .. 'f'}):
      return "'" & value & "' is not a check of activities"
    p.check = value
    ""
  let spec = Spec[Params](
    opts:
      @[flag(Params, ["-h", "--help"], help), bitsOption, checkOption] &
      webOptions(Params, web)
  )
  template fail(msg: string) =
    result.problem = msg
    return

  let why = parseOptions(args, spec, result)
  if why.len > 0:
    fail(why)
  let combination = webProblem(result.web)
  if combination.len > 0:
    fail(combination)
  if result.check.len > 0 and result.bits.len == 0:
    fail("--check goes with --bits")
