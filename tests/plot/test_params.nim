import std/[options, strutils, unittest]
import nimchoo/packages/plot/params
import nimchoo/packages/util/args/args
import nimchoo/packages/web/webopts

suite "plot: the command line":
  test "the subject, the period, the frames of --file":
    let p = parseArgs(
      @[
        "ff", "--after", "2018-08-01", "--before", "2018-09-01", "--file", "--frames",
        "form",
      ]
    ).params
    check p.subject == some("ff") and p.firstDay == some(1533081600'i64) and
      p.lastDay == some(1535673600'i64) and p.frames == @["form"] and
      p.web.kind == wkFile
    check parseArgs(@[]).params.subject.isNone
  test "problems":
    check parseArgs(@["a", "b"]).problem.contains("at most one SUBJECT")
    check parseArgs(@["--after", "2018-09-01", "--before", "2018-08-02"]).problem
      .contains("not before")
    check parseArgs(@["--after", "yesterday"]).problem.contains("is a day")
    check parseArgs(@["--frame", "x"]).problem.contains("goes with `--worker`")
    check parseArgs(@["--frames", "x"]).problem.contains(
      "chooses the files of `--file`"
    )
    check parseArgs(@["--model", "x"]).problem.contains("unexpected option")
