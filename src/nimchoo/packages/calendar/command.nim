## `nch calendar`: the activities on a calendar, a row for each month and the days in columns by weekday (weeks start on
## Monday).  It shows the selection (see `nch activities --select`), or with `--all` every activity with the
## selection in blue.  It takes no criteria, like `climbs` and `map`: to see a calendar of some activities, select them first.

import std/[options, strutils, terminal, times]
import ../../core/[errors, globals]
import ../activities/[rows, table]
import ../ui/[live, style, vocabulary]
import ../user/session
import ../util/args/[args, usage]
import ./[calendar, params]

{.push raises: [].}

const commandName* = "calendar" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch calendar`, described (for tab completion).
  calendarSpec().docs

const
  synopsis = "usage: nch [--db PATH] [--user NAME] calendar [--all] [-v]"
  intro =
    """The activities of the selection (see `nch activities --select`) on a calendar: a row for each month that has one,
the days in columns by weekday (weeks start on Monday).  White: a day with an activity; blue: a day with one in the
selection; grey: none.  The months either side of a gap are marked (a yellow name, or a * without colour), as are the
months that were left out."""

proc usageText*(width: int): string =
  ## The usage: the introduction and the options, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" &
    optionLines(calendarSpec().docs, width).join("\n") & "\n"

proc skippedWarning(rows: seq[ListRow], zone: Timezone): seq[Line] =
  ## The last line of a calendar of the months with data, if it left some out.
  let n = skippedMonths(rows, zone)
  if n > 0:
    result.add @[
      span(
        "warning: " & $n & (if n == 1: " month" else: " months") &
          " with no activity not shown, at the yellow month names; use --verbose to show them",
        yellow,
      )
    ]

proc lines*(
    st: Session, p: Params, zone: Timezone, screen: Screen
): seq[Line] {.raises: [StoreError].} =
  ## The calendar of the selection, or of every activity, and its last line.
  let rows =
    if p.all:
      allRows(st, p.verbose)
    else:
      selectionRows(st, p.verbose)
  if rows.len == 0:
    return @[
      plain(
        "nothing is selected: `nch calendar --all` shows every activity; `nch activities CRITERIA --select` chooses some"
      )
    ]
  result = calendarLines(rows, zone, p.verbose, screen)
  result.add footerLine(
    rows, (if p.all: some(rows.len) else: none(int)), selectedColour
  )
  if not p.verbose:
    result.add skippedWarning(rows, zone)

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch calendar ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch calendar", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch calendar", e.msg)
  try:
    let colour = canColourStdout()
    let screen = Screen(
      colour: colour,
      width:
        if isatty(stdout):
          terminalWidth()
        else:
          0,
    )
    for l in lines(st, p, local(), screen):
      stdout.say render(l, colour) & "\n"
    exitOk
  except StoreError as e:
    failure("nch calendar", e.msg)
  finally:
    st.close()
