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
