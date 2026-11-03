## The command line of `nch heatmap`, parsed.  Pure.  Every option has a value in
## the result (the defaults are written out), because the options are what the
## files are named after (see cache.nim).

import std/[math, strutils]
import ../cache
import ../serve/webopts

{.push raises: [].}

const
  defaultStyle* = "lines"
  defaultToleranceM* = 5.0
  maxToleranceM* = 1000.0

type Params* = object
  key*: string          ## the key of the selection to draw ("": the current one)
  style*: string        ## how to draw it
  toleranceM*: float    ## how far a simplified route may stray (metres; 0: not simplified)
  web*: WebArgs         ## --worker, --web and what goes with it
  help*: bool
  problem*: string      ## "" if the command line was fine

func metres*(x: float): string =
  ## 5.0 -> "5", 2.5 -> "2.5": the form used in file names.
  if x == floor(x): $int(x) else: $x

func parseArgs*(args: seq[string]): Params =
  ## `--key KEY`, `--style lines`, `--tolerance METRES`, `--worker`, `--web` (with `--no-open`,
  ## `--port N`, `--new-token`), `-h`.
  result = Params(style: defaultStyle, toleranceM: defaultToleranceM, web: initWebArgs())
  var i = 0
  template fail(msg: string) =
    result.problem = msg
    return
  template value(name: string): string =
    inc i
    if i >= args.len: fail(name & " needs a value")
    args[i]
  while i < args.len:
    let a = args[i]
    var issue = ""
    if takeWebOption(args, i, result.web, issue):
      if issue.len > 0: fail(issue)
      inc i
      continue
    case a
    of "-h", "--help": result.help = true
    of "--key":
      let v = value(a)
      if not isOptionValue(v): fail("'" & v & "' is not a selection key")
      result.key = v
    of "--style":
      let v = value(a)
      if v != "lines": fail("the only style is 'lines', not '" & v & "'")
      result.style = v
    of "--tolerance":
      let v = value(a)
      var t = -1.0
      try:
        t = parseFloat(v)
      except ValueError:
        discard
      if not (t >= 0.0 and t <= maxToleranceM):
        fail("--tolerance is a number of metres from 0 to " & metres(maxToleranceM) &
             ", not '" & v & "'")
      result.toleranceM = t
    else:
      fail("unexpected argument " & a)
    inc i
  let combination = webProblem(result.web)
  if combination.len > 0: fail(combination)
