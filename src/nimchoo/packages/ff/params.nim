## The command line of `nch ff`, parsed.  Pure.

import std/[options, strutils, times]
import ../util/args/args
import ../model/completion
import ../web/[request, webopts]

{.push raises: [].}

type
  Params* = object
    model*: Option[string] ## none: the default model
    fromDay*, toDay*: Option[int64]
      ## a calendar date, as Unix seconds at its start in UTC (it is a day of the timezone used)
    hourly*: bool
    utc*: bool ## days and times in UTC, not the computer's timezone
    fitnessScale*, fatigueScale*: float
    stdout*: bool ## print the CSV, not write a file
    web*: WebMode ## `--file`, `--worker` and the options of serving

  Raw = object ## what the options fill in
    help, hourly, utc, stdout: bool
    model: string
    fromDay, toDay: Option[int64]
    fitnessScale, fatigueScale: float
    web: WebArgs

proc parseDay*(s: string): Option[int64] =
  ## `2018-08-27`, as the start of that UTC day.
  if s.len != 10:
    return
  try:
    return some(parse(s, "yyyy-MM-dd", utc()).toTime.toUnix)
  except TimeParseError, ValueError:
    discard

const
  positive = 5.0e-324 # (the smallest number above 0)
  scaleText = "a number above 0"

func ffSpec*(): Spec[Raw] =
  ## The options of `nch ff`, with the web options.  The ones a page may be given in its address say so: the server's
  ## list of them is made from here (`web/request.pageOf`).
  Spec[Raw](
    opts:
      @[
        text(
          Raw,
          ["--model"],
          model,
          "NAME",
          "the model to use (default: `default`)",
          completion = completesFrom(completeModels),
          address = adValue,
          valid = anyWord,
        ),
        custom(
          Raw,
          ["--from"],
          true,
          "DAY",
          "the first day to show, like 2018-08-27 (default: the first with an impulse)",
          address = adValue,
          valid = day,
          body = (
            block:
              let d = parseDay(value)
              if d.isNone:
                return refuse(name & " is a day, like 2018-08-27 (not '" & value & "')")
              p.fromDay = d
              fine
          ),
        ),
        custom(
          Raw,
          ["--to"],
          true,
          "DAY",
          "the last day to show (default: today)",
          address = adValue,
          valid = day,
          body = (
            block:
              let d = parseDay(value)
              if d.isNone:
                return refuse(name & " is a day, like 2018-08-27 (not '" & value & "')")
              p.toDay = d
              fine
          ),
        ),
        flag(
          Raw,
          ["--hourly"],
          hourly,
          "one row an hour instead, labelled by the end of the hour (with its offset from UTC: 2018-08-27T14:00:00-03:00)",
          address = adFlag,
        ),
        flag(
          Raw,
          ["--utc"],
          utc,
          "days and times in UTC, not this computer's timezone",
          address = adFlag,
        ),
        flag(Raw, ["--stdout"], stdout, "print the CSV instead of making a file"),
      ] & webOptions(Raw, web, "the chart", "CSV") &
      @[
        number(
          Raw,
          ["--fitness-scale"],
          fitnessScale,
          positive,
          1.0e12,
          scaleText,
          "S",
          "multiply the fitness by S (default 1)",
          address = adValue,
          valid = plainNumber,
        ),
        number(
          Raw,
          ["--fatigue-scale"],
          fatigueScale,
          positive,
          1.0e12,
          scaleText,
          "S",
          "multiply the fatigue by S (default 1; the original program used 5, to make the two curves look alike)",
          address = adValue,
          valid = plainNumber,
        ),
        helpFlag(Raw),
      ]
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.fromDay.isSome and raw.toDay.isSome and raw.fromDay.get > raw.toDay.get:
    return problemWith[Params]("--from is after --to")
  if raw.stdout and (raw.web.file or raw.web.worker):
    return problemWith[Params]("--stdout cannot be used with --file or --worker")
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.problem)
  if raw.stdout and (raw.web.noOpen or raw.web.newToken or raw.web.port != defaultPort):
    return problemWith[Params](
      "--no-open, --new-token and --port are for serving the page: they cannot be used with --stdout"
    )
  parsedOk(
    Params(
      model: (if raw.model.len > 0: some(raw.model) else: none(string)),
      fromDay: raw.fromDay,
      toDay: raw.toDay,
      hourly: raw.hourly,
      utc: raw.utc,
      fitnessScale: raw.fitnessScale,
      fatigueScale: raw.fatigueScale,
      stdout: raw.stdout,
      web: mode.params,
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## The options of `nch ff`.
  parseCommand(
    args, ffSpec(), Raw(web: initWebArgs(), fitnessScale: 1, fatigueScale: 1), finish
  )
