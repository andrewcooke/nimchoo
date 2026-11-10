## The command line of `nch calendar`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type Params* = object
  all*: bool ## `--all`: every activity, not only the selection
  verbose*: bool ## `-v`: every month from the first to the last
  help*: bool
  problem*: string

func calendarSpec*(): Spec[Params] =
  ## The options of `nch calendar`, each with its help.
  Spec[Params](
    opts: @[
      flag(Params, ["--all"], all).documented(
        "",
        "every activity, with those in the selection in blue; without it only the selection is shown",
      ),
      flag(Params, ["-v", "--verbose"], verbose).documented(
        "",
        "every month from the first to the last, not only those with an activity (the months either side of a gap are marked otherwise)",
      ),
      flag(Params, ["-h", "--help"], help).documented("", "show this help"),
    ]
  )

proc parseArgs*(args: seq[string]): Params =
  ## `nch calendar [--all] [-v]`.
  result.problem = parseOptions(args, calendarSpec(), result)
