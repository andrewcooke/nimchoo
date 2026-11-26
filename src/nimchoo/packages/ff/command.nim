## `nch ff`: the models, the named sets of variables of the training impulse and of the fitness and fatigue curves
## (see calc.nim), and the models selection.  A model is an editable type (`editable`: listed by name, added, edited,
## deleted) and a subject (its selection follows the steps of `subject/steps`).  The built-in model, `default`, is made by the
## program and selected for every user from the start; otherwise it is like the others.  The impulses of a model are worked out when they are wanted (see `nch ff`).

import std/[options, sequtils, strformat]
import ../../core/[ask, globals]
import ../user/session
import ../db/store
import ../ui/vocabulary
import ../util/args/[args, usage]
import ../../core/errors
import ../../core/logfile
import ../editable/editable
import ../subject/steps
import ../tags/tag
import ./[calc, models, params]

{.push raises: [].}

const commandName* = "ff" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch ff`, described (for tab completion).
  modelSpec().docs

const synopsis =
  """usage: nch [--db PATH] [--user NAME] ff [--names PATTERN... [--within | --also]] [--select]
       nch [--db PATH] [--user NAME] ff --all [--select]
       nch [--db PATH] [--user NAME] ff [--names PATTERN... [--within] | --all] --delete
       nch [--db PATH] ff --add NAME [--base NAME] [VALUES]
       nch [--db PATH] ff --edit NAME [--rename NEW] [VALUES]"""

func intro(): seq[Line] =
  @[
    ~"Show the models selection: the models whose fitness, fatigue and form the views show.  A model is a named set of the variables of the training impulse and of the curves made from it, and of which activities count (by their tags).  The program makes one, `default` (the original's), selected for every user from the start; it can be edited or deleted like any other (a rebuild makes it again), or copied (`--add NAME --base default`, then the values that differ).  Models belong to no user; the selection is each user's.",
    ~"With `--names` (or `--all`), the models listed are found in these steps:",
    ~"1. Start with all the models.",
    step(2, withinStep(words)),
    ~"3. Keep those whose names match any of the patterns.",
    step(4, alsoStep(words)),
    ~"5. If `--delete`, delete the result, and stop.",
    step(6, selectStep(words)),
    step(7, displayStep(words)),
    ~"If no criteria are given, the steps are skipped and the models selection is used.  `--add` copies `default` unless `--base` names another model; a model keeps no tie to the one it was copied from.  An edit that changes the impulse (`--gamma`, `--zero`, `--one`, `--max-gap`, `--zones`) deletes the impulses worked out with the model, and they are worked out again when wanted.",
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(synopsis, width, intro(), modelSpec().docs)

proc patternsOf(names: seq[string]): seq[TagPattern] =
  for n in names:
    result.add parsePattern(n).pattern.get # (checked by the parse)

proc found(
    st: Session, a: Action[Model], s: Steps
): seq[Model] {.raises: [StoreError].} =
  ## What the steps find: with no criteria and no `--all`, the selection.
  if s.meansSelection(a.names.len > 0):
    selectedModels(st.db, st.userId)
  else:
    searchModels(st.db, st.userId, patternsOf(a.names), s.among, s.also)

proc list(
    g: Globals, st: Session, a: Action[Model], s: Steps
): int {.raises: [StoreError].} =
  let shown = found(st, a, s)
  if s.select:
    st.writing(
      proc() {.closure, raises: [StoreError].} =
        replaceModelSelection(st.db, st.userId, shown.mapIt(it.id))
    )
  let chosen = selectedModels(st.db, st.userId).mapIt(it.id)
  let marks = not g.colour[osOut]
  g.showAll(
    osOut,
    table(modelKind(), shown, shown.mapIt(it.id in chosen), g.textWidth(osOut), marks),
  )
  let isSelection = s.select or s.meansSelection(a.names.len > 0)
  let total = loadModels(st.db).len
  g.done(listDone(shown.len, some(total), "model", "models", isSelection, marks))
  exitOk

proc add(g: Globals, st: Session, a: Action[Model]): int {.raises: [StoreError].} =
  if findModel(st.db, a.name).isSome:
    return failure(g, "nch ff", ~"there is a model called {a.name} already")
  var base = defaultModel()
  if a.base.isSome:
    let b = findModel(st.db, a.base.get)
    if b.isNone:
      return failure(
        g, "nch ff", ~"there is no model called {a.base.get} (see `nch ff --all`)"
      )
    base = b.get
  var m = made(modelKind(), a, base)
  m.builtIn = false
  let why = problem(m)
  if why.isSome:
    return failure(g, "nch ff", why.get)
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      discard insertModel(st.db, m)
  )
  let said = fmt"made the model {m.name}"
  g.log.log(lvInfo, commandName, leSaved, said)
  g.done(plain(said))
  exitOk

proc edit(g: Globals, st: Session, a: Action[Model]): int {.raises: [StoreError].} =
  let old = findModel(st.db, a.target)
  if old.isNone:
    return
      failure(g, "nch ff", ~"there is no model called {a.target} (see `nch ff --all`)")
  let m = edited(modelKind(), a, old.get)
  if a.newName.isSome:
    let other = findModel(st.db, m.name)
    if other.isSome and other.get.id != m.id:
      return failure(g, "nch ff", ~"there is a model called {other.get.name} already")
  let why = problem(m)
  if why.isSome:
    return failure(g, "nch ff", why.get)
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      updateModel(st.db, old.get, m)
  )
  let again =
    if sameImpulse(old.get, m):
      ""
    else:
      " (its impulses will be worked out again when wanted)"
  let said = fmt"changed the model {m.name}{again}"
  g.log.log(lvInfo, commandName, leSaved, said)
  g.done(plain(said))
  exitOk

proc delete(
    g: Globals, st: Session, a: Action[Model], s: Steps, yOrN: YesOrNo
): int {.raises: [StoreError].} =
  let doomed = found(st, a, s)
  if doomed.len == 0:
    g.warn(~"no model to delete")
    return exitOk
  let names = sayList(doomed.mapIt(it.name))
  let what =
    if doomed.len == 1:
      fmt"the model {names}"
    else:
      fmt"{doomed.len} models, {names}"
  let refused = askDelete(g, fmt"{what}, with their impulses", yOrN)
  if refused.isSome:
    return refused.get
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      deleteModels(st.db, doomed.mapIt(it.id))
  )
  let said = fmt"deleted {what}"
  g.log.log(lvInfo, commandName, leDeleted, said)
  g.sayDeleted(said)
  exitOk

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch ff ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch ff", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch ff", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch ff", e.msg)
  try:
    case p.action.kind
    of akList:
      list(g, st, p.action, p.steps)
    of akAdd:
      add(g, st, p.action)
    of akEdit:
      edit(g, st, p.action)
    of akDelete:
      delete(g, st, p.action, p.steps, parsed.yOrN)
  except StoreError as e:
    failure(g, "nch ff", e.msg)
  finally:
    st.close()
