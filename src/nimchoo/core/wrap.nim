## Words wrapped to a width: for the usage texts, and for the lists `nch packages` prints.  Pure.

import std/strutils

{.push raises: [].}

func wrap*(text: string, width: int): seq[string] =
  ## `text` broken into lines of at most `width` characters at spaces (a longer word has a line of its own).  A
  ## newline in the text starts a new line.  Two spaces after a full stop stay two, unless the line ends there.
  for paragraph in text.split('\n'):
    var line = ""
    for word in paragraph.split(' '):
      if line.len == 0:
        line = word
      elif line.len + 1 + word.len <= width:
        line.add " " & word
      else:
        result.add line.strip(leading = false)
        line = word
    result.add line.strip(leading = false)

func prose*(text: string, width: int): string =
  ## Paragraphs of text wrapped to `width`: the paragraphs are separated by a blank line, and a line break inside one is
  ## only where the source was broken, so it becomes a space.  (For the introduction and the notes of a usage.)
  var paragraphs: seq[string]
  for p in text.strip(chars = {'\n'}).split("\n\n"):
    paragraphs.add wrap(p.replace('\n', ' '), width).join("\n")
  paragraphs.join("\n\n")
