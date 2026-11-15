## The command line of `nch calendar`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type
  Params* = object
    verbose*: bool ## `-v`: every month from the first to the last

  Raw = object ## what the options fill in
    help, verbose: bool

func calendarSpec*(): Spec[Raw] =
  ## The options of `nch calendar`.
  Spec[Raw](
    opts: @[
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
  parsedOk(Params(verbose: raw.verbose))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch calendar [-v]`.
  parseCommand(args, calendarSpec(), Raw(), finish)
