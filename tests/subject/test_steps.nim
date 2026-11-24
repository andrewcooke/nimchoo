import std/[options, sequtils, strutils, unittest]
import nimchoo/core/[line, optdoc]
import nimchoo/packages/util/args/args
import nimchoo/packages/subject/[steps, subjects]
import nimchoo/packages/activities/criteria as activityCriteria
import nimchoo/packages/climbs/params as climbParams

const things = Words(
  command: "things",
  things: "things",
  every: "every thing",
  selection: "things selection",
)

type Raw = object
  help, criteria: bool
  steps: Steps

proc finish(raw: Raw): Parsed[Steps] {.nimcall, raises: [].} =
  let wrong = stepProblem(raw.steps, raw.criteria, things)
  if wrong.isSome:
    return problemWith[Steps](wrong.get)
  parsedOk(raw.steps)

func spec(): Spec[Raw] =
  Spec[Raw](
    opts:
      @[flag(Raw, ["--criterion"], criteria, plain("a criterion"))] &
      stepOptions(Raw, things) & @[helpFlag(Raw)]
  )

proc parse(args: varargs[string]): Parsed[Steps] =
  parseCommand(@args, spec(), Raw(), finish)

suite "subject: the steps that involve the selection":
  test "each option sets its step; --within searches the selection":
    let p = parse("--criterion", "--within", "--select")
    check p.kind == pkOk and p.params.within and p.params.select and
      p.params.among == amSelection
    check parse("--criterion", "--also").params.among == amEvery
    check parse("--all", "--select").params == Steps(all: true, select: true)
  test "the rules, each named in the subject's words":
    check parse("--select").problem.contains("needs criteria or `--all`")
    check parse("--also").problem.contains("adds the things selection")
    check parse("--within", "--all").problem.contains("one or the other")
    check parse("--criterion", "--within", "--also").problem.contains(
      "together they are the things selection itself (`nch things`)"
    )
    check parse("--criterion", "--also", "--select").kind == pkOk
  test "the help and the usage's steps name the subject":
    let helps = spec().docs.mapIt(it.help.text).join("\n")
    check "every thing, not just the things selection" in helps
    check step(2, withinStep(things)).text ==
      "2. If --within, keep only those in the current things selection."
  test "activities and climbs take the same options from here":
    for (names, docs) in [
      ("activities", activityCriteria.criteriaSpec().docs),
      ("climbs", climbParams.climbSpec().docs),
    ]:
      for o in ["--all", "--select", "--also", "--within"]:
        check docs.countIt(o in it.names) == 1

suite "subject: when the selection itself is meant":
  test "no criteria and no --all":
    check Steps().meansSelection(criteria = false)
    check not Steps().meansSelection(criteria = true)
    check not Steps(all: true).meansSelection(criteria = false)
