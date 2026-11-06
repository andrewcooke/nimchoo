## The command line of `nch heatmap`, parsed.  Pure.  Every option has a value in
## the result (the defaults are written out), because the options are what the
## files are named after (see cache.nim).

import ../cli/args
import std/[math, strutils]
import ../cache
import ../serve/webopts

{.push raises: [].}

const
  defaultStyle* = "lines"
  defaultToleranceM* = 5.0
  maxToleranceM* = 1000.0

type Params* = object
  check*: string        ## the hash of the selection that must still be the current one ("": no check)
  style*: string        ## how to draw it
  toleranceM*: float    ## how far a simplified route may stray (metres; 0: not simplified)
  web*: WebArgs         ## --worker, --web and what goes with it
  help*: bool
  problem*: string      ## "" if the command line was fine

func metres*(x: float): string =
  ## 5.0 -> "5", 2.5 -> "2.5": the form used in file names.
  if x == floor(x): $int(x) else: $x

proc parseArgs*(args: seq[string]): Params =
  ## `--check HASH`, `--style lines`, `--tolerance METRES`, `--worker`, `--web` (with `--no-open`,
  ## `--port N`, `--new-token`), `-h`.
  result = Params(style: defaultStyle, toleranceM: defaultToleranceM, web: initWebArgs())
  let checkOption = custom(Params, ["--check"], true):
    if not isOptionValue(value): return "'" & value & "' is not a selection hash"
    p.check = value
    ""
  let styleOption = custom(Params, ["--style"], true):
    if value != "lines": return "the only style is 'lines', not '" & value & "'"
    p.style = value
    ""
  let toleranceOption = custom(Params, ["--tolerance"], true):
    var t = 0.0
    if not parseFloatIn(value, 0.0, maxToleranceM, t):
      return "--tolerance is a number of metres from 0 to " & metres(maxToleranceM) &
             ", not '" & value & "'"
    p.toleranceM = t
    ""
  let spec = Spec[Params](opts: @[
    flag(Params, ["-h", "--help"], help), checkOption, styleOption, toleranceOption] &
    webOptions(Params, web))
  template fail(msg: string) =
    result.problem = msg
    return
  let why = parseOptions(args, spec, result)
  if why.len > 0: fail(why)
  let combination = webProblem(result.web)
  if combination.len > 0: fail(combination)
