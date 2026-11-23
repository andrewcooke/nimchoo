## The command line of `nch calendar`, parsed.  Pure.  `nch calendar [SUBJECT] [--detail N] [--shade NAME]`: the subject is
## what the calendar is of (the default one if it is left out); which subjects and shades exist is the registry's to say
## (`subject/subjects`, `calendar/shades`), so the command checks the names, not the parser.

import std/[options, strutils]
import ../../core/[extension, globals]
import ../util/args/args
import ../subject/subjects
import ./[calendar, frames]

{.push raises: [].}

type
  Params* = object
    detail*: Option[Detail] ## none: as the shade asks (`--detail`)
    shade*: Option[string] ## `--shade NAME`
    subject*: Option[string] ## none: the default subject

  Raw = object ## what the options fill in
    help: bool
    detail: Option[Detail]
    shade: string
    subjects: seq[string]

func completeShades(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The names of the shades that start with what is typed.
  for s in g.extensions.get(calendarShadePoint):
    if s.name.startsWith(typed):
      result.add s.name

func calendarSpec*(): Spec[Raw] =
  ## The options of `nch calendar`.
  Spec[Raw](
    opts: @[
      custom(
        Raw,
        ["--detail"],
        true,
        "N",
        ~"which months: 1, those with a marked day; 2, every month from the first to the last; 3, every month from the first to this one (default: 3 for the shades that are curves, fitness, fatigue and form; else 1)",
        body = (
          block:
            case value
            of "1":
              p.detail = some(dtData)
            of "2":
              p.detail = some(dtRange)
            of "3":
              p.detail = some(dtToNow)
            else:
              return refuse(~"`{name}` is 1, 2 or 3 (not '{value}')")
            fine
        ),
      ),
      text(
        Raw,
        ["--shade"],
        shade,
        "NAME",
        ~"colour the background of each day by a value (see the table below): from the theme's NAME-lo (the lowest shown) to NAME-hi (the highest), or default-lo to default-hi.  Needs colour",
        completion = completesFrom(completeShades),
        valid = isWord,
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      takeSubject(p.subjects, arg),
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.subjects.len > 1:
    return problemWith[Params](tooManySubjects)
  if raw.shade.len > 0 and not isWord(raw.shade):
    return problemWith[Params](~"'{raw.shade}' is not a name of a shade")
  parsedOk(
    Params(
      detail: raw.detail,
      shade: (if raw.shade.len > 0: some(raw.shade) else: none(string)),
      subject: (if raw.subjects.len == 1: some(raw.subjects[0])
      else: none(string)),
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch calendar [SUBJECT] [--detail N] [--shade NAME]`.
  parseCommand(args, calendarSpec(), Raw(), finish)
