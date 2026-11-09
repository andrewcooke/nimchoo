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

suite "vocabulary: the looks":
  test "the ones that matter":
    check look(leImported) == Look(colour: green)
    check look(leSaved) == look(leImported)
    check look(leFailed) == Look(colour: red, bold: true)
    check look(leAdvisory) == Look(colour: yellow)
    check look(leDuplicate) == Look(colour: grey)
    check look(leUnchanged) == look(leDuplicate)
  test "the server's words: served is dim, denied is red":
    check look(leServed) == Look(colour: grey)
    check look(leDenied) == Look(colour: red)
  test "bookkeeping words are dim":
    for e in [leStart, leRun, leExit, leDone, leNote]:
      check look(e) == Look(colour: grey)
  test "a span takes the look of its event":
    check span("x", leFailed).look == look(leFailed)
    check span("x", leFailed).text == "x"
  test "no two of the words that carry a meaning in colour look the same":
    check look(leImported) != look(leFailed)
    check look(leFailed) != look(leAdvisory)
    check look(leAdvisory) != look(leDuplicate)
