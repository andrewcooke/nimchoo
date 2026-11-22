## The command line of `nch calendar`, parsed.  Pure.  `nch calendar [SUBJECT] [-v]`: the subject is what the calendar is of
## (the default one if it is left out); which subjects exist is the registry's to say (`subject/subjects`), so the command
## checks the name, not the parser.

import std/[options, strformat]
import ../util/args/args
import ../subject/subjects

{.push raises: [].}

type
  Params* = object
    verbose*: bool ## `-v`: every month from the first to the last
    subject*: Option[string] ## none: the default subject

  Raw = object ## what the options fill in
    help, verbose: bool
    subjects: seq[string]

func calendarSpec*(): Spec[Raw] =
  ## The options of `nch calendar`.
  Spec[Raw](
    opts: @[
      flag(
        Raw,
        ["-v", "--verbose"],
        verbose,
        ~"every month from the first to the last, not only those with an activity (the months either side of a gap are marked otherwise)",
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      takeSubject(p.subjects, arg),
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.subjects.len > 1:
    return problemWith[Params](tooManySubjects)
  parsedOk(
    Params(
      verbose: raw.verbose,
      subject:
        if raw.subjects.len == 1:
          some(raw.subjects[0])
        else:
          none(string),
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch calendar [SUBJECT] [-v]`.
  parseCommand(args, calendarSpec(), Raw(), finish)
