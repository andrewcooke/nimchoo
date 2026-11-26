import std/[options, unittest]
import nimchoo/core/[ask, globals, line]

func keys(typed: string): KeyReader =
  var at = 0
  result = proc(): Option[char] {.raises: [].} =
    if at < typed.len:
      inc at
      some(typed[at - 1])
    else:
      none(char)

let q = @[plain("delete 3 activities?")]
let g = Globals(offline: true)

suite "ask: the one question":
  test "with -y it is yes at once, whatever the terminal, and no key is read":
    var read = false
    let reader = proc(): Option[char] {.raises: [].} =
      read = true
      some('n')
    check ask(g, q, false, ynYes, true, reader) and ask(
      g, q, true, ynYes, false, reader
    )
    check not read
  test "with --no it is no at once, whatever the terminal, and no key is read":
    var read = false
    let reader = proc(): Option[char] {.raises: [].} =
      read = true
      some('y')
    check not ask(g, q, true, ynNo, true, reader) and
      not ask(g, q, true, ynNo, false, reader)
    check not read
  test "on a terminal: y, n and Enter (the default); other keys wait; Ctrl-C, Ctrl-D and the end are no":
    for (typed, default, answer) in [
      ("y", false, true),
      ("Y", false, true),
      ("n", true, false),
      ("N", true, false),
      ("\r", true, true),
      ("\n", false, false),
      ("x 1y", false, true),
      ("\3", true, false),
      ("\4", true, false),
      ("", true, false),
      ("xz", true, false),
    ]:
      check ask(g, q, default, ynAsk, true, keys(typed)) == answer
  test "not on a terminal and without -y it is no, and nothing is read":
    var read = false
    let reader = proc(): Option[char] {.raises: [].} =
      read = true
      some('y')
    check not ask(g, q, true, ynAsk, false, reader)
    check not read

suite "askDelete: the confirmation of every --delete":
  test "yes goes ahead; a refusal is the failure exit code":
    check askDelete(g, "it", ynYes).isNone
    check askDelete(g, "it", ynNo) == some(exitFailure)
