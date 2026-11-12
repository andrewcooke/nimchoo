## What another package may offer `nch activities`: a criterion, an option that picks activities.  This is an extension
## point of this package (`activityCriterion`): `climbs` offers `--climbs`, which needs the climbs of the database, so the
## command cannot know it.  A contribution is the option's description (names, value, help: it shows in `--help`, and is
## parsed like the options of the command) and `resolve`, which turns what was given into a condition on the activities.
##
## The condition is a boolean SQL expression over `a` (the activity) and `f` (its file); the command joins it with the
## others by `and`, and `--invert` negates the whole.  Its pieces carry the package that wrote them (`db/sqltext`), so the
## command may run it though it could not read the tables the condition reads.

import ../../core/[errors, extension]
import ../db/sqltext
import ../user/session
import ../util/args/args

{.push raises: [].}

type
  Resolution* = object ## What `resolve` made of the words given to the option.
    condition*: Sql ## true for the activities that meet it
    notes*: seq[string]
      ## said before the list, to tell what the words came to ("" lines are not said)

  ResolveProc* =
    proc(st: Session, values: seq[string]): Resolution {.nimcall, raises: [StoreError].}
    ## Raises `StoreError` with the sentence to say if the words mean nothing ("no climb has 'x' in its name").

  Criterion* = object
    doc*: OptDoc
      ## the option: `names`, `metavar`, `help`, how many words it takes (`arity`), what completes it
    resolve*: ResolveProc

  Contributed* = object
    ## An option of a contribution as it was given on the command line.
    option*: string ## the first name of the option
    values*: seq[string]
    resolve*: ResolveProc

const activityCriterion* = ExtensionPoint[Criterion](name: "activities/criteria")
  ## The criteria that packages offer `activities`.
