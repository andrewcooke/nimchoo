## The commands `nch` has: the one place that says what they are.  The list in the usage text, the dispatch, the
## words the log's command column holds, and the commands the web server may run are all made from (or checked
## against) this enum, so a command cannot be in one and missing from another.  Adding a command: a member here,
## its summary below, and a branch in `dispatch` (src/nch.nim), which the compiler demands.

import std/[options, strutils]

{.push raises: [].}

type Command* = enum
  cmActivities = "activities"
  cmClimbs = "climbs"
  cmUsers = "users"
  cmModels = "models"
  cmLandmarks = "landmarks"
  cmMap = "map"
  cmFf = "ff"
  cmFit = "fit"
  cmLog = "log"
  cmCache = "cache"
  cmDb = "db"

const summaries*: array[Command, string] = [
  cmActivities: "the activities: show them, choose the ones other commands use",
  cmClimbs: "the climbs of the selected activities, with times and ranks",
  cmUsers: "the users: make, rename, set the threshold heart rate",
  cmModels: "the models: sets of variables for the training impulse",
  cmLandmarks: "places of your own, named: they come before every other name",
  cmMap: "the routes of the selected activities and their climbs, on a map",
  cmFf: "the fitness and fatigue curves, as CSV for plotting",
  cmFit: "read a FIT file and print it",
  cmLog: "show the log, filtered, with the events coloured",
  cmCache:
    "the files outside the database (downloads, generated files): show them, delete them",
  cmDb: "the database file: where it is and how big, or delete it",
]

func parseCommand*(name: string): Option[Command] =
  ## The command called `name`, if there is one.
  for c in Command:
    if $c == name:
      return some(c)

func commandList*(): string =
  ## The lines of the usage text that name the commands.
  for c in Command:
    result.add "  " & ($c).alignLeft(11) & " " & summaries[c] & "\n"
