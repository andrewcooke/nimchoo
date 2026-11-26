## An activity's sport is its `sport:` tag: an import gives it from what the file says (`sport:cycling:road`, `step.nim`),
## and the user may change it (`sport:cycling:gravel`).  The one place that reads it, for every command that shows the
## sport (the list, the map, the climbs' attempts, the plot's runs, the question before a delete).  Pure.

import std/strutils

{.push raises: [].}

const sportKey* = "sport:" ## what a tag that says the sport starts with

func sportSql*(activity = "a.id"): string =
  ## SQL for the sport of the activity whose id is the column `activity`: its tag without `sport:` ("cycling:road"),
  ## as given; the first, in the order of their folded forms, if it has several; '' if none.  (`activity` is a column's
  ## name, not a value.)
  "coalesce((select substr(tag, " & $(sportKey.len + 1) &
    ") from activity_tag where activity_id = " & activity & " and folded like '" &
    sportKey & "%' order by folded limit 1), '')"

func sportParts*(text: string): tuple[sport, subSport: string] =
  ## What `sportSql` gives as the sport and the sub-sport: "cycling:road" is ("cycling", "road"); what follows a second
  ## `:` is part of the sub-sport.
  let i = text.find(':')
  if i < 0:
    (text, "")
  else:
    (text[0 ..< i], text[i + 1 .. ^1])
