## The command line of `nch ff`, parsed, and the declaration of a model as an editable type (`editable`), from which
## the options, the parse and the table are made.  Pure.

import std/[options, strformat, strutils]
import ../../core/line
import ../util/args/args
import ../ui/[markup, units]
import ../editable/editable
import ../subject/steps
import ../tags/tag
import ./[calc, completion]

{.push raises: [].}

const words* = Words(
  command: "ff", things: "models", every: "every model", selection: "models selection"
) ## how the models are named in the steps that involve their selection

type
  Raw* = editable.Raw[Model]

  Params* = object
    ## What is asked: an action, and (to list or delete) the steps of the search.
    action*: Action[Model]
    steps*: Steps

func parseNumber(name, value: string, x: var float): Problem =
  if not parseFloatIn(value, -1.0e12, 1.0e12, x):
    return valueIs(name, "a number", value)
  fine

func parseSeconds(name, value: string, x: var int): Problem =
  let t = parseTimeSpan(value)
  if t.isNone or t.get.inSeconds != float(int(t.get.inSeconds)):
    return
      valueIs(name, "a duration in whole seconds with its unit (`60s`, `2m`)", value)
  x = int(t.get.inSeconds)
  fine

func parseDays(name, value: string, x: var float): Problem =
  let t = parseTimeSpan(value)
  if t.isNone:
    return valueIs(name, "a duration with its unit (`42d`, `36h`)", value)
  x = t.get.inDays
  fine

func parseZones(name, value: string, x: var array[5, float]): Problem =
  let parts = value.split(',')
  if parts.len == 5:
    var ok = true
    for k, part in parts:
      if not parseFloatIn(part, -1.0e12, 1.0e12, x[k]):
        ok = false
    if ok:
      return fine
  refuse(
    ~"`{name}` is five percentages of the threshold heart rate, like 68,83,94,105,121 (not '{value}')"
  )

func parsePatterns(name: string, values: seq[string], x: var seq[TagPattern]): Problem =
  x = @[]
  for v in values:
    let (p, why) = parsePattern(v)
    if why.isSome:
      return refuse(plain(why.get))
    x.add p.get
  fine

func showSeconds(s: int): string =
  fmt"{s}"

func showZones(z: array[5, float]): string =
  for i, x in z:
    if i > 0:
      result.add '/'
    result.add plainNumber(x)

func showPatterns(ps: seq[TagPattern]): Line =
  for k, p in ps:
    if k > 0:
      result.add span(" ")
    result.add ~"<tag {p}>"

func modelNameProblem(text: string): Option[string] =
  parseTag(text).problem

func isModelName*(text: string): bool =
  ## Whether a text can be a model's name: written as a tag is.
  modelNameProblem(text).isNone

func modelPatternProblem(text: string): Option[string] =
  parsePattern(text).problem

func modelNameOf(m: Model): string =
  m.name

func renameModel(m: var Model, name: string) =
  m.name = name

func modelCheck(m: Model): Option[string] =
  problem(m)

func modelKind*(): Kind[Model] =
  ## A model, as an editable type: its attributes (each an option of `--add` and `--edit`, and a column).
  Kind[Model](
    one: "model",
    many: "models",
    nameOf: modelNameOf,
    rename: renameModel,
    nameProblem: modelNameProblem,
    patternProblem: modelPatternProblem,
    check: modelCheck,
    names: completesFrom(completeModels),
    attrs: @[
      valueAttr(
        Model,
        "--gamma",
        gamma,
        "G",
        ~"the power in impulse = ((zone - ZERO) / (ONE - ZERO)) ^ G  (default 2)",
        "gamma",
        parseNumber,
        plainNumber,
      ),
      valueAttr(
        Model,
        "--zero",
        zero,
        "Z",
        ~"the zone with no impulse (default 1)",
        "zero",
        parseNumber,
        plainNumber,
      ),
      valueAttr(
        Model,
        "--one",
        one,
        "O",
        ~"the zone with an impulse of 1 per 10 seconds (default 6)",
        "one",
        parseNumber,
        plainNumber,
      ),
      valueAttr(
        Model,
        "--max-gap",
        maxSecs,
        "DURATION",
        ~"the longest gap in heart rate that is bridged, with its unit (default 60s; `2m`; whole seconds; a bare number is taken as seconds, after asking)",
        "max_gap_s",
        parseSeconds,
        showSeconds,
        unitText = "s",
      ),
      valueAttr(
        Model,
        "--zones",
        zones,
        "A,B,C,D,E",
        ~"the upper limits of zones 1 to 5, as percentages of the user's threshold heart rate (default 68,83,94,105,121)",
        "zones_%",
        parseZones,
        showZones,
        rightAligned = false,
      ),
      valueAttr(
        Model,
        "--ceiling",
        ceiling,
        "PERCENT",
        ~"readings above this percentage of the threshold heart rate are a fault of the sensor, and are ignored (default 125)",
        "ceiling_%",
        parseNumber,
        plainNumber,
      ),
      valueAttr(
        Model,
        "--fitness-decay",
        fitnessDays,
        "DURATION",
        ~"the decay time of fitness, with its unit (default 42d; a bare number is taken as days, after asking)",
        "fitness_decay_d",
        parseDays,
        plainNumber,
        unitText = "d",
      ),
      valueAttr(
        Model,
        "--fatigue-decay",
        fatigueDays,
        "DURATION",
        ~"the decay time of fatigue, with its unit (default 7d; a bare number is taken as days, after asking)",
        "fatigue_decay_d",
        parseDays,
        plainNumber,
        unitText = "d",
      ),
      valueAttr(
        Model,
        "--fitness-scale",
        fitnessScale,
        "S",
        ~"the weight of fitness in form = FITNESS-SCALE * fitness - FATIGUE-SCALE * fatigue (default 1)",
        "fitness_scale",
        parseNumber,
        plainNumber,
      ),
      valueAttr(
        Model,
        "--fatigue-scale",
        fatigueScale,
        "S",
        ~"the weight of fatigue in form (default 5)",
        "fatigue_scale",
        parseNumber,
        plainNumber,
      ),
      listAttr(
        Model,
        "--tags",
        patterns,
        "PATTERN...",
        ~"the activities that count: those with a tag matching every pattern (`sport:cycling*`); none (`--tags` alone, the default) counts them all",
        "tags",
        parsePatterns,
        showPatterns,
      ),
    ],
  )

func modelSpec*(): Spec[Raw] =
  ## The options of `nch ff`.
  let kind = modelKind()
  Spec[Raw](
    opts: options(kind) & stepOptions(Raw, words) & @[helpFlag(Raw)],
    hint: proc(arg: string): Line {.nimcall, raises: [].} =
      ~" (to add a model: `--add {arg}`; to choose models by name: `--names {arg}`)",
  )

func finish(raw: Raw): Parsed[Params] =
  let action = actionOf(raw)
  if action.kind != pkOk:
    return Parsed[Params](kind: pkProblem, why: action.why)
  let a = action.params
  let s = raw.steps
  let anyStep = s.all or s.select or s.also or s.within
  if a.kind in {akAdd, akEdit} and anyStep:
    return problemWith[Params](
      ~"`--all`, `--select`, `--also` and `--within` choose models to list or delete: not with `--add` or `--edit`"
    )
  if a.kind == akDelete and (s.select or s.also):
    return problemWith[Params](
      ~"`--delete` shows nothing: it does not go with `--select` or `--also` (it is too easy to delete more than was meant)"
    )
  let wrong = stepProblem(s, a.names.len > 0, words)
  if wrong.isSome:
    return problemWith[Params](wrong.get)
  if s.all and a.names.len > 0:
    return problemWith[Params](~"`--all` is every model: it does not go with `--names`")
  parsedOk(Params(action: a, steps: s))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch ff` (the models selection); `--names PATTERN...` or `--all`, with the steps (`--select`, `--within`,
  ## `--also`) or `--delete`; `--add NAME [--base NAME]` or `--edit NAME [--rename NEW]` with values.
  parseCommand(args, modelSpec(), Raw(kind: modelKind(), draft: defaultModel()), finish)
