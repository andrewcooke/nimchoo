import std/[os, sequtils, strutils, times, unittest]
import nimchoo/core/globals
import nimchoo/packages/calendar/[calendar, command as calendarCommand, params]
import nimchoo/packages/db/statement
import nimchoo/packages/ui/style
import nimchoo/packages/user/session
import nimchoo/packages/util/args/args
from nimchoo/registry import allFragments, allAccess, newAllAccess

let dir = getTempDir() / "nch-test-calendar-cmd"

const
  july1 = 1530446400 # 2018-07-01T12:00Z, cycling, selected
  aug27 = 1535371200 # 2018-08-27T12:00Z, running

proc addActivity(s: Session, tag: string, startT: int, sport: string) =
  s.db.execute(
    "insert into file(user_id, name, sha256, imported_at) values (:userId, :name, :sha256, 0)",
    userId = s.userId,
    name = tag,
    sha256 = tag,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_t, end_t, sport, distance_m, timer_s) select max(id), 0, :startT, :endT, :sport, 1000.0, 600.0 from file",
    startT = startT,
    endT = startT + 100,
    sport = sport,
  )

proc world(name: string): Session =
  ## The default user has a ride on 1 July 2018, which is selected, and a run on 27 August, which is not.
  removeDir(dir / name)
  result = openSession(dir / name / "x.db", allFragments, access = allAccess)
  result.addActivity("ride", july1, "cycling")
  result.addActivity("run", aug27, "running")
  result.db.execute(
    "insert into selection(user_id, activity_id) select :userId, min(id) from activity",
    userId = result.userId,
  )

func texts(ls: seq[Line]): seq[string] =
  for l in ls:
    result.add l.text

let screen = Screen(colour: true)

suite "nch calendar: the command line":
  test "--all and -v":
    check parseArgs(@[]).params.all == false
    let p = parseArgs(@["--all", "-v"])
    check p.problem == "" and p.params.all and p.params.verbose
  test "no criteria, no other options":
    check parseArgs(@["--sport", "cycling"]).problem.len > 0
    check parseArgs(@["x"]).problem.len > 0
  test "every option has help and is in the usage":
    for d in calendarSpec().docs:
      check d.help.len > 0
    let text = calendarCommand.usageText(80)
    for d in calendarSpec().docs:
      for n in d.names:
        check n in text
  test "the whole usage fits the width, except the synopsis":
    for width in [50, 80]:
      for l in calendarCommand.usageText(width).splitLines:
        if not l.startsWith("usage: "):
          check l.len <= width
  test "exit codes":
    let g = Globals(fragments: allFragments, access: allAccess)
    check calendarCommand.run(g, @["--help"]) == exitOk
    check calendarCommand.run(g, @["--nonesuch"]) == exitUsage

suite "nch calendar: what it shows":
  test "the selection alone: the months and days of what is selected, in the colour of the selection":
    let s = world("selection")
    defer:
      s.close()
    let ls = lines(s, parseArgs(@[]).params, utc(), screen)
    check ls[0].text.startsWith("    Mo Tu We")
    check ls.texts.filterIt(it.startsWith("Jul ")).len == 1
    check ls.texts.filterIt(it.startsWith("Aug ")).len == 0
    let jul = ls.filterIt(it.text.startsWith("Jul "))[0]
    check jul.anyIt(it.look.colour == blue and it.text == "01 ")

  test "--all: every activity, those in the selection in blue, and how many of how many":
    let s = world("all")
    defer:
      s.close()
    let ls = lines(s, parseArgs(@["--all"]).params, utc(), screen)
    check ls.texts.filterIt(it.startsWith("Jul ")).len == 1 and
      ls.texts.filterIt(it.startsWith("Aug ")).len == 1
    check ls.texts[^1].startsWith("done: 2 of 2 activities, 1 match selected, ")
    let aug = ls.filterIt(it.text.startsWith("Aug "))[0]
    check aug.anyIt(it.look.colour == white and it.text == "27 ")

  test "months left out are warned of, until -v shows them":
    let s = world("skip")
    defer:
      s.close()
    s.db.execute(
      "update activity set start_t = 1520640000 where id = (select min(id) from activity)"
    ) # 2018-03-10
    let ls = lines(s, parseArgs(@["--all"]).params, utc(), screen)
    check ls.texts[^1] ==
      "warning: 4 months with no activity not shown, at the yellow month names; use --verbose to show them"
    check ls[^1][0].look.colour == yellow
    let all = lines(s, parseArgs(@["--all", "-v"]).params, utc(), screen)
    check all.texts.filterIt(it[0 .. 3] in ["Apr ", "May ", "Jun ", "Jul "]).len == 4
    check not all.texts[^1].startsWith("warning")

  test "an empty selection says what to do":
    let s = world("empty")
    defer:
      s.close()
    s.db.execute("delete from selection")
    let ls = lines(s, parseArgs(@[]).params, utc(), screen)
    check ls.len == 1 and "nothing is selected" in ls[0].text and "--all" in ls[0].text
