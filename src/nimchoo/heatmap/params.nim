## The command line of `nch heatmap`, parsed.  Pure.  Every option has a value in
## the result (the defaults are written out), because the options are what the
## files are named after (see cache.nim).

import std/[math, strutils]
import ../cache

{.push raises: [].}

const
  defaultStyle* = "lines"
  defaultToleranceM* = 5.0
  maxToleranceM* = 1000.0

type Params* = object
  sel*: string          ## the selection to draw ("": the current one)
  style*: string        ## how to draw it
  toleranceM*: float    ## how far a simplified route may stray (metres; 0: not simplified)
  worker*: bool         ## for programs: make the files, print the page's path, then the data's
  help*: bool
  problem*: string      ## "" if the command line was fine

func metres*(x: float): string =
  ## 5.0 -> "5", 2.5 -> "2.5": the form used in file names.
  if x == floor(x): $int(x) else: $x

func parseArgs*(args: seq[string]): Params =
  ## `--sel KEY`, `--style lines`, `--tolerance METRES`, `--worker`, `-h`.
  result = Params(style: defaultStyle, toleranceM: defaultToleranceM)
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
    case a
    of "-h", "--help": result.help = true
    of "--worker": result.worker = true
    of "--sel":
      let v = value(a)
      if not isOptionValue(v): fail("'" & v & "' is not a selection key")
      result.sel = v
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
