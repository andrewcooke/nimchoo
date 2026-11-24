import std/[options, os, sequtils, strutils, times, unittest]
from std/unicode import runeLen
import nimchoo/core/[globals, theme]
import nimchoo/packages/calendar/[calendar, command as calendarCommand, frames, params]
import nimchoo/core/extension
import nimchoo/packages/fit/time
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
    "insert into file(user_id, name, sha256, imported_epoch) values (:userId, :name, :sha256, 0)",
    userId = s.userId,
    name = tag,
    sha256 = tag,
  )
  s.db.execute(
    "insert into activity(file_id, session, start_epoch, end_epoch, sport, distance_m, timer_s, riding_start_epoch, riding_end_epoch) select max(id), 0, :startT, :endT, :sport, 1000.0, 600.0, :startT, :endT from file",
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
    "insert into activity_selection(user_id, activity_id) select :userId, min(id) from activity",
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
  lines(
    s,
    choose(g, p).params,
    g.extensions.get(calendarDaysPoint),
    p,
    utc(),
    screen,
    UnixTime(2_000_000_000),
  )

suite "nch calendar: the command line":
  test "--detail 1 to 3, and a shade; -v and --all are gone":
    check parseArgs(@[]).params.detail.isNone and parseArgs(@[]).params.shade.isNone
    let p = parseArgs(@["--detail", "2", "--shade", "fitness"])
    check p.problem == "" and p.params.detail == some(dtRange) and
      p.params.shade == some("fitness")
    check parseArgs(@["--detail", "4"]).problem.contains("1, 2 or 3")
    check parseArgs(@["-v"]).problem.len > 0
    check parseArgs(@["--all"]).problem.len > 0
  test "a shade is the registry's: an unknown one says what there are":
    let p = choose(g, parseArgs(@["--shade", "nonesuch"]).params)
    check "no shade 'nonesuch'" in p.problem and "fitness" in p.problem and
      "impulse" in p.problem
    check calendarCommand.run(g, @["--shade", "nonesuch"]) == exitUsage
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
    let text = calendarCommand.usageText(g, 80).plainText
    for d in calendarSpec().docs:
      for n in d.names:
        check n in text
  test "the whole usage fits the width, except the synopsis":
    for width in [50, 80]:
      for l in calendarCommand.usageText(g, width).plainText.splitLines:
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
    check ls.texts[^1].startsWith("done: 1 of ") # (the activities' frame sums them up)

  test "months left out are warned of, until -v shows them":
    let s = world("skip")
    defer:
      s.close()
    s.db.execute(
      "update activity set start_epoch = 1520640000 where id = (select min(id) from activity)"
    ) # 2018-03-10
    s.db.execute(
      "insert or ignore into activity_selection(user_id, activity_id) select :userId, id from activity",
      userId = s.userId,
    ) # (both are selected now)
    let ls = s.shown()
    check ls.texts[^1] ==
      "warning: 4 months with nothing marked omitted; --detail 2 shows them"
    check styleOf(ls[^1][0]) == "warn"
    let all = s.shown("--detail", "2")
    check all.texts.filterIt(it[0 .. 3] in ["Apr ", "May ", "Jun ", "Jul "]).len == 4
    check not all.texts[^1].startsWith("warning")

  test "an empty selection is a warning, not a failure":
    let s = world("empty")
    s.db.execute("delete from activity_selection")
    s.close()
    let quiet = Globals(
      fragments: allFragments,
      access: allAccess,
      extensions: extensions,
      dbPath: some(dir / "empty" / "x.db"),
      offline: true,
    )
    check calendarCommand.run(quiet, @[]) == exitOk

suite "nch calendar --shade: what it needs":
  test "colour, and a theme with the colours of a shade; else a failure that says so":
    let path = getTempDir() / "nch-test-calendar-shade.db"
    removeFile(path)
    var h = Globals(
      dbPath: some(path),
      fragments: allFragments,
      access: allAccess,
      extensions: extensions,
    )
    check calendarCommand.run(h, @["--shade", "fitness"]) == exitFailure # (no colour)
    h.colour = [true, true]
    check calendarCommand.run(h, @["--shade", "fitness"]) == exitFailure
      # (colour, but a theme with no default-0 or fitness-0)
    h.theme = parseTheme("default-0 bg=#000000\ndefault-1 bg=#ffffff\n")
    check calendarCommand.run(h, @["--shade", "fitness"]) == exitOk
      # (nothing is selected: said, and no failure)
