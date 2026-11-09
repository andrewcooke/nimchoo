## The commands `nch` has: the one place that says what they are.  The list in the usage text, the dispatch, the
## words the log's command column holds, and the commands the web server may run are all made from (or checked
## against) this enum, so a command cannot be in one and missing from another.  Adding a command: a member here,
## its summary below, and a branch in `dispatch` (src/nch.nim), which the compiler demands.

import std/[algorithm, options, strutils]

{.push raises: [].}

type Command* = enum
  cmActivities = "activities"
  cmClimbs = "climbs"
  cmUsers = "users"
  cmModels = "models"
  cmLandmarks = "landmarks"
  cmMap = "map"
  cmFf = "ff"

const summaries*: array[Command, string] = [
  cmActivities: "the activities: show them, choose the ones other commands use",
  cmClimbs: "the climbs of the selected activities, with times and ranks",
  cmUsers: "the users: make, rename, set the threshold heart rate",
  cmModels: "the models: sets of variables for the training impulse",
  cmLandmarks: "places of your own, named: they come before every other name",
  cmMap: "the routes of the selected activities and their climbs, on a map",
  cmFf: "the fitness and fatigue curves, as CSV for plotting",
]

func parseCommand*(name: string): Option[Command] =
  ## The command called `name`, if there is one.
  for c in Command:
    if $c == name:
      return some(c)

func commandList*(others: openArray[(string, string)]): string =
  ## The lines of the usage text that name the commands, by name: these, and `others` (name, summary), the
  ## commands that the registry provides.
  var all: seq[(string, string)] = @others
  for c in Command:
    all.add (name: $c, summary: summaries[c])
  all.sort(
    proc(a, b: (string, string)): int =
      cmp(a[0], b[0])
  )
  for (name, summary) in all:
    result.add "  " & name.alignLeft(11) & " " & summary & "\n"
