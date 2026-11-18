import std/[options, os, sequtils, strutils, times, unittest]
from std/unicode import runeLen
import nimchoo/core/globals
import nimchoo/packages/calendar/[calendar, command as calendarCommand, params]
import nimchoo/packages/db/statement
import nimchoo/packages/ui/style
import nimchoo/packages/user/session
import nimchoo/packages/util/args/args
import ../support/styles
from nimchoo/registry import allFragments, allAccess, newAllAccess, extensions

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
let g = Globals(fragments: allFragments, access: allAccess, extensions: extensions)

proc shown(s: Session, args: varargs[string]): seq[Line] =
  ## The lines `nch calendar ARGS` shows, in UTC.
  let p = parseArgs(@args).params
  lines(s, choose(g, p).params, p, utc(), screen)

suite "nch calendar: the command line":
  test "-v; --all is gone (the calendar is of the selection)":
    check parseArgs(@[]).params.verbose == false
    let p = parseArgs(@["-v"])
    check p.problem == "" and p.params.verbose
    check parseArgs(@["--all"]).problem.len > 0
  test "a subject, at most one; no criteria, no other options":
    check parseArgs(@["activities"]).params.subject.get == "activities"
    check parseArgs(@[]).params.subject.isNone
    check parseArgs(@["a", "b"]).problem.len > 0
    check parseArgs(@["Not-a-word"]).problem.len > 0
    check parseArgs(@["--sports", "cycling"]).problem.len > 0
  test "the subject is the registry's: the default is the activities, and an unknown one says what there is":
    check choose(g, parseArgs(@[]).params).params.subject.name == "activities"
    let p = choose(g, parseArgs(@["nonesuch"]).params)
    check "no subject 'nonesuch'" in p.problem and "activities" in p.problem
    check calendarCommand.run(g, @["nonesuch"]) == exitUsage
  test "every option has help and is in the usage":
    for d in calendarSpec().docs:
      check d.help.len > 0
    let text = calendarCommand.usageText(g, 80)
    for d in calendarSpec().docs:
      for n in d.names:
        check n in text
  test "the whole usage fits the width, except the synopsis":
    for width in [50, 80]:
      for l in calendarCommand.usageText(g, width).splitLines:
        if not l.startsWith("usage: "):
          check l.runeLen <= width
  test "exit codes":
    check calendarCommand.run(g, @["--help"]) == exitOk
    check calendarCommand.run(g, @["--nonesuch"]) == exitUsage

suite "nch calendar: what it shows":
  test "the selection alone: the months and days of what is selected, in the colour of the selection":
    let s = world("selection")
    defer:
      s.close()
    let ls = s.shown()
    check ls[0].text.startsWith("    Mo Tu We")
    check ls.texts.filterIt(it.startsWith("Jul ")).len == 1
    check ls.texts.filterIt(it.startsWith("Aug ")).len == 0
    let jul = ls.filterIt(it.text.startsWith("Jul "))[0]
    check jul.anyIt(styleOf(it) == "select" and it.text == "01")
    check ls.texts[^1].startsWith("done: 1 activity")
      # (the activities' frame sums them up)

  test "months left out are warned of, until -v shows them":
    let s = world("skip")
    defer:
      s.close()
    s.db.execute(
      "update activity set start_t = 1520640000 where id = (select min(id) from activity)"
    ) # 2018-03-10
    s.db.execute(
      "insert or ignore into selection(user_id, activity_id) select :userId, id from activity",
      userId = s.userId,
    ) # (both are selected now)
    let ls = s.shown()
    check ls.texts[^1] ==
      "warning: 4 months with no activity not shown; use --verbose to show them"
    check styleOf(ls[^1][0]) == "warn"
    let all = s.shown("-v")
    check all.texts.filterIt(it[0 .. 3] in ["Apr ", "May ", "Jun ", "Jul "]).len == 4
    check not all.texts[^1].startsWith("warning")

  test "an empty selection says what to do":
    let s = world("empty")
    defer:
      s.close()
    s.db.execute("delete from selection")
    let ls = s.shown()
    check ls.texts ==
      @["the selection of activities is empty (see `nch activities --select`)"]
