import std/[options, os, sets, strutils, unittest]
import nimchoo/core/line
import nimchoo/packages/ui/style
import nimchoo/packages/ui/vocabulary

suite "vocabulary: the events":
  test "each has its own word, and the word finds it again":
    var words: HashSet[string]
    for e in LogEvent:
      check ($e).len > 0
      check $e notin words
      words.incl $e
      check parseEvent($e) == some(e)
  test "an unknown word is none":
    for w in ["", "warning", "Failed", "failed ", "imports"]:
      check parseEvent(w).isNone

suite "vocabulary: the styles":
  test "the ones that matter":
    check $style(leImported) == "good"
    check style(leSaved) == style(leImported)
    check $style(leFailed) == "bad"
    check $style(leAdvisory) == "warn"
    check $style(leDuplicate) == "hide"
    check style(leUnchanged) == style(leDuplicate)
  test "the server's words: served is hidden, denied is bad":
    check $style(leServed) == "hide"
    check $style(leDenied) == "bad"
  test "bookkeeping words are hidden":
    for e in [leStart, leRun, leExit, leDone, leNote]:
      check $style(e) == "hide"
  test "a span takes the style of its event":
    check span("x", leFailed).styles == @[style(leFailed)]
    check span("x", leFailed).text == "x"
  test "no two of the words that carry a meaning have the same style":
    check style(leImported) != style(leFailed)
    check style(leFailed) != style(leAdvisory)
    check style(leAdvisory) != style(leDuplicate)
  test "the selection has a style of its own":
    check $selectedStyle == "select"

suite "vocabulary: the last line of a list":
  test "how many, of how many if known, the noun agreeing with the last number":
    check listDone(11, some 1113, "activity", "activities").plainText ==
      "11 of 1,113 activities"
    check listDone(1, some 1, "climb", "climbs").plainText == "1 of 1 climb"
    check listDone(3, none(int), "user", "users").plainText == "3 users"
    check listDone(1, none(int), "user", "users").plainText == "1 user"
    check listDone(0, some 30, "package", "packages").plainText == "0 of 30 packages"
    check listDone(2, none(int), "activity", "activities", extra = ", 1.0km").plainText ==
      "2 activities, 1.0km"
  test "the count is in the selection's style when the list is the selection":
    check listDone(2, none(int), "x", "xs", selected = true)[0].styles ==
      @[selectedStyle]
    check listDone(2, none(int), "x", "xs")[0].styles.len == 0
  test "every list command ends with it":
    # (a source check, as the rule is one of the helpers: a list that builds its own last line is the next drift)
    for (file, lister) in [
      ("packages/user/command.nim", "userLines"),
      ("packages/names/command.nim", "landmarkLines"),
      ("packages/names/command.nim", "suggestionLines"),
      ("introspect.nim", "summaryLines"),
      ("packages/climbs/command.nim", "countLive"),
      ("packages/activities/table.nim", "footerLine"),
    ]:
      let text = readFile(
        currentSourcePath().parentDir.parentDir.parentDir / "src" / "nimchoo" / file
      )
      check lister in text
      check "listDone" in text
