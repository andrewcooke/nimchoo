import std/[options, sets, unittest]
import nimchoo/ui/[style, vocabulary]

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
    check look(leImported) == Look(fg: cGreen)
    check look(leSaved) == look(leImported)
    check look(leFailed) == Look(fg: cRed, bold: true)
    check look(leAdvisory) == Look(fg: cYellow)
    check look(leDuplicate).dim and look(leDuplicate).fg == cNone
    check look(leUnchanged) == look(leDuplicate)
  test "bookkeeping words are dim":
    for e in [leStart, leRun, leExit, leDone, leNote]:
      check look(e) == Look(dim: true)
  test "a span takes the look of its event":
    check span("x", leFailed).look == look(leFailed)
    check span("x", leFailed).text == "x"
  test "no two of the words that carry a meaning in colour look the same":
    check look(leImported) != look(leFailed)
    check look(leFailed) != look(leAdvisory)
    check look(leAdvisory) != look(leDuplicate)
