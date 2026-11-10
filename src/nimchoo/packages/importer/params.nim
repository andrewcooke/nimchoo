## The command line of `nch import`, parsed.  Pure.

import ../util/args/args

{.push raises: [].}

type
  Params* = object
    paths*: seq[string] ## the files and folders to import (at least one)
    quiet*, slow*: bool ## -q, --slow: how to import
    jobs*: int ## -j: threads to import with (0: the default)

  Raw = object ## what the options fill in
    help, quiet, slow: bool
    jobs: int
    paths: seq[string]

func importSpec*(): Spec[Raw] =
  ## The options of `nch import`.
  Spec[Raw](
    opts: @[
      flag(Raw, ["-q", "--quiet"], quiet, "report only failures and the summary"),
      flag(
        Raw,
        ["--slow"],
        slow,
        "read and check every file, even those unchanged since last time (finds files that were moved or copied; retries failures)",
      ),
      whole(
        Raw,
        ["-j", "--jobs"],
        jobs,
        1,
        256,
        "a number of threads, 1 to 256",
        "N",
        "use N threads to read and decode the files (the database is written by one thread, in the order of the files, so the result is the same); 1: no threads.  Default: the number of processors, but not more than 8",
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      p.paths.add arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.paths.len == 0:
    return problemWith[Params]("nch import needs at least one path")
  parsedOk(Params(paths: raw.paths, quiet: raw.quiet, slow: raw.slow, jobs: raw.jobs))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch import [-q] [--slow] [-j N] PATH...`.
  parseCommand(args, importSpec(), Raw(), finish)
