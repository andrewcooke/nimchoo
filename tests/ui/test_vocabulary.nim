import std/[options, sets, unittest]
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
