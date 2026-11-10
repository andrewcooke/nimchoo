## The command line of `nch import`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type Params* = object
  paths*: seq[string] ## the files and folders to import
  quiet*, slow*: bool ## -q, --slow: how to import
  jobs*: int ## -j: threads to import with (0: the default)
  help*: bool
  problem*: string

proc parseArgs*(args: seq[string]): Params =
  ## `nch import [-q] [--slow] [-j N] PATH...`.
  let spec = Spec[Params](
    opts: @[
      flag(Params, ["-h", "--help"], help),
      flag(Params, ["-q", "--quiet"], quiet),
      flag(Params, ["--slow"], slow),
      whole(Params, ["-j", "--jobs"], jobs, 1, 256, "a number of threads, 1 to 256"),
    ],
    positional: proc(p: var Params, arg: string): string {.nimcall, raises: [].} =
      p.paths.add arg
      "",
  )
  result.problem = parseOptions(args, spec, result)
  if result.problem.len == 0 and not result.help and result.paths.len == 0:
    result.problem = "nch import needs at least one path"
