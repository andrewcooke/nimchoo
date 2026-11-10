## `nch models`: the models, the named sets of variables of the training-impulse calculation
## (see calc.nim), and the making of new ones.  Models belong to no user.  The impulses of a
## model are worked out when they are wanted (see `nch ff`), not when the model is added.
##
import std/[options, strutils]
import ../../core/globals
import ../db/store
import ../ui/live
import ../util/args/[args, usage]
import ../../core/errors
import ../../core/logfile
import ./params
import ./calc
import ./models

{.push raises: [].}

const commandName* = "models" ## what the user types after `nch`

const
  synopsis = """usage: nch [--db PATH] models
       nch [--db PATH] models --add NAME [--gamma G] [--zero Z] [--one O] [--max-secs S]
                             [--zones A,B,C,D,E] [--fitness-days D] [--fatigue-days D]"""
  intro =
    """Without options, show the models.  A model is a named set of the variables of the training impulse and of the
fitness and fatigue curves made from it.  A model is never changed once it is made: add another.  Variables not given
are those of the `default` model."""

proc usageText*(width: int): string =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(modelSpec().docs, width).join("\n") & "\n"

func num(x: float): string =
  ## Without a pointless decimal part.
  let s = formatFloat(x, ffDecimal, 4)
  result = s.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})

func zones(m: Model): string =
  for i, z in m.zones:
    if i > 0:
      result.add '/'
    result.add num(z)

proc modelLines*(ms: seq[Model]): seq[string] =
  ## The models, one to a line.
  let head =
    ["model", "gamma", "zero", "one", "max_secs", "zones_%", "fitness_d", "fatigue_d"]
  var rows: seq[array[8, string]]
  for m in ms:
    rows.add [
      m.name,
      num(m.gamma),
      num(m.zero),
      num(m.one),
      $m.maxSecs,
      zones(m),
      num(m.fitnessDays),
      num(m.fatigueDays),
    ]
  var w: array[8, int]
  for c in 0 .. 7:
    w[c] = head[c].len
    for r in rows:
      w[c] = max(w[c], r[c].len)
  proc line(cells: array[8, string]): string =
    for c in 0 .. 7:
      if c > 0:
        result.add "  "
      result.add (
        if c == 0 or c == 5: cells[c].alignLeft(w[c])
        else: cells[c].align(w[c])
      )
    result = result.strip(leading = false)

  result.add line(head)
  for r in rows:
    result.add line(r)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch models ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch models", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch models", e.msg)
  try:
    case p.action
    of maList:
      for l in modelLines(loadModels(st.db)):
        stdout.say l & "\n"
      exitOk
    of maAdd:
      if findModel(st.db, p.model.name).isSome:
        return failure(
          "nch models", "there is a model called '" & p.model.name & "' already"
        )
      insertModel(st.db, p.model)
      let said = "made the model " & p.model.name
      g.log.log(lvInfo, commandName, leSaved, said)
      stdout.say said & "\n"
      exitOk
  except StoreError as e:
    failure("nch models", e.msg)
