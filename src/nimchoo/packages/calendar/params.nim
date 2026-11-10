## The command line of `nch calendar`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type
  Params* = object
    all*: bool ## `--all`: every activity, not only the selection
    verbose*: bool ## `-v`: every month from the first to the last

  Raw = object ## what the options fill in
    help, all, verbose: bool

func calendarSpec*(): Spec[Raw] =
  ## The options of `nch calendar`.
  Spec[Raw](
    opts: @[
      flag(
        Raw,
        ["--all"],
        all,
        "every activity, with those in the selection in blue; without it only the selection is shown",
      ),
      flag(
        Raw,
        ["-v", "--verbose"],
        verbose,
        "every month from the first to the last, not only those with an activity (the months either side of a gap are marked otherwise)",
      ),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  parsedOk(Params(all: raw.all, verbose: raw.verbose))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch calendar [--all] [-v]`.
  parseCommand(args, calendarSpec(), Raw(), finish)
