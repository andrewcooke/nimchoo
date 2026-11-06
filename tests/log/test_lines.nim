import std/[options, unittest]
import nimchoo/log/lines
import nimchoo/ui/[style, vocabulary]

const
  run1 = "2026-11-02T10:00:00Z INFO  import    run        /a"
  start1 = "2026-11-02T10:00:00Z INFO  import    start      2 files"
  fail1 = "2026-11-02T10:00:01Z ERROR import    failed     /a/bad.fit  (bad format) why"
  dup1 = "2026-11-02T10:00:01Z INFO  import    duplicate  /a/x.fit  same content as /a/y.fit"
  exit1 = "2026-11-02T10:00:02Z INFO  import    exit       1"
  sel = "2026-11-02T10:05:00Z INFO  select    run        --all"
  selExit = "2026-11-02T10:05:00Z INFO  select    exit       0"
  run2 = "2026-11-02T11:00:00Z INFO  import    run        /b"
  adv2 = "2026-11-02T11:00:01Z WARN  import    advisory   /b/z.fit  offset 5: odd"
  old = "2026-11-01T15:58:42Z INFO  import  /x.fit  already imported"

proc parsed(ls: varargs[string]): seq[LogLine] =
  for l in ls: result.add parseLine(l)

func raws(s: Selected): seq[string] =
  for l in s.lines: result.add l.raw

suite "log lines: parsing":
  test "a line of the current format":
    let l = parseLine(dup1)
    check l.command == "import"
    check l.event == some(leDuplicate)
    check dup1[l.eventStart ..< l.eventEnd] == "duplicate"
  test "all levels, and a long command":
    check parseLine("2026-11-02T10:00:01Z WARN  heatmap   advisory  x").event == some(leAdvisory)
    check parseLine("2026-11-02T10:00:01Z ERROR a-longer-command  failed  x").command == "a-longer-command"
  test "lines of other shapes are kept, with no command or event":
    for raw in [old, "", "just some text", "2026-11-02T10:00:01Z INFO  import  start: 3 files",
                "2026-11-02T10:00:01Z NOISE import    failed  x", "short Z INFO  a  failed"]:
      let l = parseLine(raw)
      check l.raw == raw
      check l.event.isNone and l.command == ""
  test "an event word with other letters round it is not an event":
    check parseLine("2026-11-02T10:00:01Z INFO  import    failed:    x").event.isNone

suite "log lines: selecting":
  let all = parsed(run1, start1, fail1, dup1, exit1, sel, selExit, run2, adv2, old)

  test "no filter: every line, the old one too":
    check select(all, Filter()).raws.len == 10
  test "by command":
    check select(all, Filter(commands: @["select"])).raws == @[sel, selExit]
  test "by event; several mean any of them":
    check select(all, Filter(events: {leFailed})).raws == @[fail1]
    check select(all, Filter(events: {leFailed, leDuplicate})).raws == @[fail1, dup1]
  test "a command and events: and":
    check select(all, Filter(commands: @["import"], events: {leRun})).raws == @[run1, run2]
    check select(all, Filter(commands: @["select"], events: {leFailed})).raws.len == 0
  test "an old line matches no filter":
    check old notin select(all, Filter(events: {leImported, leFailed})).raws
    check old notin select(all, Filter(commands: @["import"])).raws
  test "the latest run of a command":
    check select(all, Filter(commands: @["import"], last: true)).raws ==
      @[run2, adv2]                                    # (the old line is not import's)
    check select(all, Filter(commands: @["select"], last: true)).raws == @[sel, selExit]
  test "the latest run of any command":
    check select(all, Filter(last: true)).raws == @[run2, adv2, old]
  test "last, then the filters":
    check select(all, Filter(commands: @["import"], events: {leFailed}, last: true)).raws.len == 0
    check select(parsed(run1, fail1, exit1, run2, adv2),
                 Filter(events: {leAdvisory}, last: true)).raws == @[adv2]
  test "no run to show":
    check select(all, Filter(commands: @["heatmap"], last: true)).noRun
    check select(@[], Filter(last: true)).noRun
    check not select(@[], Filter()).noRun
  test "the last N lines":
    check select(all, Filter(count: 2)).raws == @[adv2, old]
    check select(all, Filter(commands: @["import"], count: 1)).raws == @[adv2]
    check select(all, Filter(count: 50)).raws.len == 10
    check select(all, Filter(events: {leRun}, count: 2)).raws == @[sel, run2]

suite "log lines: styling":
  test "the event word has the look of the event, the rest is plain":
    let line = styled(parseLine(dup1))
    check line.text == dup1
    check line.len == 5
    check line[3].text == "duplicate" and line[3].look == look(leDuplicate)
    check line[0].look == Look() and line[2].look == Look() and line[4].look == Look()
    check line[1].text == "INFO" and line[1].look == levelLook("INFO")
  test "the level has its own look: ERROR red and bold, WARN yellow, INFO grey":
    check levelLook("ERROR") == Look(colour: red, bold: true)
    check levelLook("WARN") == Look(colour: yellow)
    check levelLook("INFO") == Look(colour: grey)
    check styled(parseLine(fail1))[1].text == "ERROR" and styled(parseLine(fail1))[1].look == levelLook("ERROR")
  test "each event gets its own colour":
    check styled(parseLine(fail1))[3].look == look(leFailed)
    check styled(parseLine(adv2))[3].look == look(leAdvisory)
  test "an old line is plain":
    let line = styled(parseLine(old))
    check line.len == 1 and line[0].look == Look() and line.text == old
