## Words wrapped to a width: for the documentation of the packages and the lists `nch packages` prints.  The wrapping itself
## is `line.wrapped`'s (the program has one algorithm: widths are in characters, not bytes: an accent or `₂` is one).  Pure.

import std/strutils
import ./line

{.push raises: [].}

func wrap*(text: string, width: int): seq[string] =
  ## `text` broken into lines of at most `width` characters at spaces (a longer word has a line of its own).  A
  ## newline in the text starts a new line.  Two spaces after a full stop stay two, unless the line ends there.  (The one
  ## algorithm of the program, `line.wrapped`, with no styles.)
  for l in plain(text).wrapped(width):
    result.add l.plainText

func rst*(text: string, width: int): string =
  ## Documentation (RST: paragraphs separated by a blank line, and lists whose items start with `* `) wrapped to
  ## `width`: the text of a paragraph or an item is joined and wrapped again, an item with its text under the first word.
  var blocks: seq[string]
  for para in text.strip(chars = {'\n'}).split("\n\n"):
    if para.startsWith("* "):
      var items: seq[string]
      for line in para.splitLines:
        if line.startsWith("* "):
          items.add line[2 .. ^1].strip
        elif items.len > 0:
          items[^1].add " " & line.strip
      var lines: seq[string]
      for item in items:
        for i, l in wrap(item, max(10, width - 2)):
          lines.add (if i == 0: "* " else: "  ") & l
      blocks.add lines.join("\n")
    else:
      blocks.add wrap(para.replace('\n', ' '), width).join("\n")
  blocks.join("\n\n")
