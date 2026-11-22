## The one question every confirmation is: `ask`.  What would be deleted, a unit filled in: each says what it will do and waits
## for one key (no Enter), `[Yn]` or `[yN]` (the upper case letter is what Enter means).  With `-y` the answer is yes at once;
## the question is still printed, followed by `y`, so the screen and the log show what was accepted.  Not on a terminal and
## without `-y` it is no, with the question and "use `-y` to accept": a script never deletes by accident.
##
## The terminal and the key are parameters, so that a test can drive it.

import std/[options, terminal]
import ./[globals, line]
when defined(posix):
  import std/[posix, termios]

{.push raises: [].}

type KeyReader* = proc(): Option[char] {.raises: [].}
  ## One key from the terminal (none: the input ended).

proc readKey*(): Option[char] =
  ## One key from the terminal, with no Enter and no echo; the terminal is put back as it was, whatever happens.  Ctrl-C
  ## comes as a key (the signal is off while waiting) so that it is an answer, not the end of the program with the terminal
  ## left as it was set.
  var saved: Termios
  if tcGetAttr(0, addr saved) != 0:
    return none(char)
  var raw = saved
  raw.c_lflag = raw.c_lflag and not (ICANON or ECHO or ISIG)
  raw.c_cc[VMIN] = 1.char
  raw.c_cc[VTIME] = 0.char
  if tcSetAttr(0, TCSANOW, addr raw) != 0:
    return none(char)
  try:
    var c: char
    if read(0, addr c, 1) == 1:
      result = some(c)
    else:
      result = none(char)
  finally:
    discard tcSetAttr(0, TCSANOW, addr saved)

proc ask*(
    g: Globals, question: seq[Line], default, yes, terminal: bool, key: KeyReader
): bool =
  ## Say the `question` (its lines, on stderr) and take the answer: with `yes` it is yes; on a `terminal` one key: `y` or `Y`
  ## yes, `n` or `N` no, Enter the `default`, Ctrl-C, Ctrl-D and the end of the input no, any other key waits; otherwise no.
  doAssert question.len > 0
  for l in question[0 ..< question.high]:
    g.show(osErr, l)
  let last = question[^1]
  if yes:
    g.show(osErr, last & @[span(" "), span("y")])
    return true
  if not terminal:
    g.show(osErr, last)
    g.show(osErr, @[span("use "), span("-y", "code"), span(" to accept")])
    return false
  let choice = if default: "[Yn]" else: "[yN]"
  g.prompt(osErr, last & @[span(" "), span(choice, "warn"), span(" ")])
  var answer = false
  while true:
    let k = key()
    if k.isNone or k.get in {'n', 'N', '\3', '\4'}:
      break
    if k.get in {'y', 'Y'}:
      answer = true
      break
    if k.get in {'\r', '\n'}:
      answer = default
      break
  g.show(osErr, plain(if answer: "y" else: "n"))
  answer

proc ask*(g: Globals, question: seq[Line], default, yes: bool): bool =
  ## `ask` on the real terminal: stdin and stderr are terminals.
  ask(g, question, default, yes, isatty(stdin) and isatty(stderr), readKey)
