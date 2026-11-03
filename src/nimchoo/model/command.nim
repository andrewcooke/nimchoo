## `nch model`: the models, the named sets of variables of the training-impulse calculation
## (see calc.nim), and the making of new ones.  Models belong to no user.  The impulses of a
## model are worked out for every activity with heart rate whose user has a threshold heart
## rate, when the model is added.
##
## This module is newer than `heartrate` and `user`: it reads their tables.

import std/[options, strutils]
import ../cli/common
import ../db/store
import ../errors
import ../ui/logfile
import ./[calc, impulses, models, params]

{.push raises: [].}

const usage* = """usage: nch [--db PATH] model
       nch [--db PATH] model --add NAME [--gamma G] [--zero Z] [--one O] [--max-secs S]
                             [--zones A,B,C,D,E] [--fitness-days D] [--fatigue-days D]

Without options, show the models.  A model is a named set of the variables of the training
impulse and of the fitness and fatigue curves made from it.  A model is never changed once it
is made: add another.  Variables not given are those of the `default` model.

  --add NAME         make a model called NAME
  --gamma G          the power in impulse = ((zone - ZERO) / (ONE - ZERO)) ^ G  (default 2)
  --zero Z           the zone with no impulse (default 1)
  --one O            the zone with an impulse of 1 per 10 seconds (default 6)
  --max-secs S       the longest gap in heart rate that is bridged, in seconds (default 60)
  --zones A,B,C,D,E  the upper limits of zones 1 to 5, as percentages of the user's
                     threshold heart rate (default 68,83,94,105,121)
  --fitness-days D   the decay time of the fitness curve (default 42)
  --fatigue-days D   the decay time of the fatigue curve (default 7)
  -h, --help         show this help
"""

func num(x: float): string =
  ## Without a pointless decimal part.
  let s = formatFloat(x, ffDecimal, 4)
  result = s.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})

func zones(m: Model): string =
  for i, z in m.zones:
    if i > 0: result.add '/'
    result.add num(z)

proc modelLines*(ms: seq[Model]): seq[string] =
  ## The models, one to a line.
  let head = ["model", "gamma", "zero", "one", "max_secs", "zones_%", "fitness_d", "fatigue_d"]
  var rows: seq[array[8, string]]
  for m in ms:
    rows.add [m.name, num(m.gamma), num(m.zero), num(m.one), $m.maxSecs, zones(m),
              num(m.fitnessDays), num(m.fatigueDays)]
  var w: array[8, int]
  for c in 0 .. 7:
    w[c] = head[c].len
    for r in rows: w[c] = max(w[c], r[c].len)
  proc line(cells: array[8, string]): string =
    for c in 0 .. 7:
      if c > 0: result.add "  "
      result.add (if c == 0 or c == 5: cells[c].alignLeft(w[c]) else: cells[c].align(w[c]))
    result = result.strip(leading = false)
  result.add line(head)
  for r in rows: result.add line(r)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch model ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch model", usage, p.problem)
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch model", e.msg)
  defer: st.close()
  try:
    if p.list:
      for l in modelLines(loadModels(st.db)): stdout.say l & "\n"
      return exitOk
    if findModel(st.db, p.model.name).isSome:
      return failure("nch model", "there is a model called '" & p.model.name & "' already")
    var done: Calculated
    st.begin()
    var committed = false
    try:
      insertModel(st.db, p.model)
      done = calculateAllMissing(st.db)
      st.commit()
      committed = true
    finally:
      if not committed: st.rollback()
    var said = "made the model " & p.model.name
    if done.hours > 0:
      said.add ", with impulses for " & $done.activities &
        (if done.activities == 1: " activity" else: " activities")
    g.log.log(lvInfo, "model", leSaved, said)
    stdout.say said & "\n"
    exitOk
  except StoreError as e:
    failure("nch model", e.msg)
