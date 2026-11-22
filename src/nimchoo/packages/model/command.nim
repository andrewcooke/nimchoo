## `nch models`: the models, the named sets of variables of the training-impulse calculation
## (see calc.nim), and the making of new ones.  Models belong to no user.  The impulses of a
## model are worked out when they are wanted (see `nch ff`), not when the model is added.
##
import std/options
import ../../core/[globals, ruled]
import ../db/store
import ../ui/[live, units]
import ../util/args/[args, usage]
import ../../core/errors
import ../../core/logfile
import ./params
import ./calc
import ./models

{.push raises: [].}

const commandName* = "models" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch models`, described (for tab completion).
  modelSpec().docs

const
  synopsis = """usage: nch [--db PATH] models
       nch [--db PATH] models --add NAME [--gamma G] [--zero Z] [--one O] [--max-gap D]
                             [--zones A,B,C,D,E] [--fitness-decay D] [--fatigue-decay D]"""
  intro = @[
    ~"Without options, show the models.  A model is a named set of the variables of the training impulse and of the fitness and fatigue curves made from it.  A model is never changed once it is made: add another.  Variables not given are those of the `default` model."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, modelSpec().docs)

func zones(m: Model): string =
  for i, z in m.zones:
    if i > 0:
      result.add '/'
    result.add plainNumber(z)

proc modelLines*(ms: seq[Model], width: int): seq[Line] =
  ## The models as a table (`core/ruled.nim`), one to a row.
  let head =
    ["model", "gamma", "zero", "one", "max_secs", "zones_%", "fitness_d", "fatigue_d"]
  var rows: seq[seq[string]]
  for m in ms:
    rows.add @[
      m.name,
      plainNumber(m.gamma),
      plainNumber(m.zero),
      plainNumber(m.one),
      $m.maxSecs,
      zones(m),
      plainNumber(m.fitnessDays),
      plainNumber(m.fatigueDays),
    ]
  ruled(@head, rows, width, right = {1, 2, 3, 4, 6, 7})

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch models ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch models", usageText(helpWidth(stderr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch models", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure(g, "nch models", e.msg)
  try:
    case p.action
    of maList:
      g.showAll(osOut, modelLines(loadModels(st.db), helpWidth(stdout)))
      exitOk
    of maAdd:
      if findModel(st.db, p.model.name).isSome:
        return
          failure(g, "nch models", ~"there is a model called '{p.model.name}' already")
      insertModel(st.db, p.model)
      let said = "made the model " & p.model.name
      g.log.log(lvInfo, commandName, leSaved, said)
      g.show(osOut, plain(said))
      exitOk
  except StoreError as e:
    failure(g, "nch models", e.msg)
