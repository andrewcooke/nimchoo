## The steps of a search of a subject's things that involve its selection, written once for every subject (activities,
## climbs): the options `--all`, `--select`, `--also` and `--within`, the rules between them, where the search looks, and
## the lines of the usage that say the steps.  The steps themselves are in CLAUDE.md ("the selection"); each command
## numbers its own list, its criteria between these.

import std/strformat
import ../../core/line
import ../ui/markup
import ../util/args/args
import ./subjects

{.push raises: [].}

type
  Steps* = object
    ## What the options of the steps say.  A command's parse state holds one, called `steps` (`stepOptions` sets it).
    all*: bool ## every one, not the selection
    select*: bool ## what is listed becomes the selection
    also*: bool ## the selection is added to what the criteria find
    within*: bool ## only the selection is searched

  Words* = object ## How a subject's things are named in the help and the messages.
    command*: string ## what is typed after `nch`: "activities"
    things*: string ## "activities"
    every*: string ## "every activity"
    selection*: string
      ## the name of its selection, with no article: "selection", "climbs selection"

func meansSelection*(s: Steps, criteria: bool): bool =
  ## Whether what is asked is the selection itself: no criteria and no `--all` (the steps are skipped).
  not criteria and not s.all

func among*(s: Steps): Among =
  ## Where the search looks.
  if s.within: amSelection else: amEvery

func allHelp(w: Words): Line =
  ~"{w.every}, not just the {w.selection}"

func selectHelp(w: Words): Line =
  ~"what is listed becomes the {w.selection}, in place of the one there was (the last of the steps above; needs criteria or `--all`)"

func alsoHelp(w: Words): Line =
  ~"add the {w.selection} to what the criteria find (after the filters and any limits): with `--select`, they are added to it"

func withinHelp(w: Words): Line =
  ~"search only the {w.selection} (before any filter): with `--select`, it is narrowed to what is found"

template stepOptions*(P: typedesc, w: Words): seq[Opt[P]] =
  ## The options of the steps, for the parse state `P` (which has a field `steps: Steps`).
  @[
    custom(P, ["--all"], false, "", allHelp(w), body = (p.steps.all = true; fine)),
    custom(
      P, ["--select"], false, "", selectHelp(w), body = (p.steps.select = true; fine)
    ),
    custom(P, ["--also"], false, "", alsoHelp(w), body = (p.steps.also = true; fine)),
    custom(
      P, ["--within"], false, "", withinHelp(w), body = (p.steps.within = true; fine)
    ),
  ]

func stepProblem*(s: Steps, criteria: bool, w: Words): Problem =
  ## What is wrong with the steps asked for, given whether there are criteria (none if nothing is).
  let command = fmt"nch {w.command}"
  if s.select and not (criteria or s.all):
    return refuse(
      ~"`--select` keeps what is listed as the {w.selection}, so it needs criteria or `--all`"
    )
  if s.also and not criteria:
    return refuse(
      ~"`--also` adds the {w.selection} to what the criteria find, so it needs criteria"
    )
  if s.within and s.all:
    return refuse(
      ~"`--within` searches the {w.selection} and `--all` {w.every}: one or the other"
    )
  if s.within and s.also:
    return refuse(
      ~"`--within` finds only selected {w.things}, and `--also` adds the {w.selection}: together they are the {w.selection} itself (<code {command}>)"
    )
  fine

func step*(n: int, line: Line): Line =
  ## A numbered line of the usage's list of steps.
  plain(fmt"{n}. ") & line

func innerStep*(n: int, line: Line): Line =
  ## A numbered line of the usage's list of steps that is repeated by the one before it (indented).
  plain(fmt"   {n}. ") & line

func placesStep*(): Line =
  ## The step that lists the places a name may mean (names/places.nim), for the usage of a command with `--from`/`--near`.
  ~"If `--from` or `--near` gives a place's name, list the places it may mean: those with that name, then those with it as a word of their name, then those with it anywhere in their name; each group the likeliest first (your landmarks, then towns, the biggest first)."

func eachPlaceStep*(first, last: int, w: Words): Line =
  ## The step that tries the places in turn, repeating the steps from `first` to `last`.
  let which =
    if first == last:
      fmt"step {first} leaves"
    else:
      fmt"steps {first} to {last} leave"
  ~"For each of those places in turn, until {which} at least one of the {w.things} (once, if there is no name; if no place does, the first is taken, and a note says so; two names are chosen one at a time, in the order given):"

func withinStep*(w: Words): Line =
  ## The step of `--within`, for the usage.
  ~"If `--within`, keep only those in the current {w.selection}."

func alsoStep*(w: Words): Line =
  ## The step of `--also`, for the usage.
  ~"If `--also`, add the current {w.selection}."

func selectStep*(w: Words): Line =
  ## The step of `--select`, for the usage.
  ~"If `--select`, replace the current {w.selection} with the result."

func displayStep*(w: Words): Line =
  ## The last step, for the usage.
  ~"Display the result (selected {w.things} are highlighted)."
