## What the tests ask of a span's styles.
import std/[sequtils, strutils]
import nimchoo/core/line

func styleOf*(s: Span): string =
  ## The innermost style of the span ("" for plain text).
  if s.styles.len == 0:
    ""
  else:
    $s.styles[^1]

func texts*(lines: seq[Line]): seq[string] =
  ## Lines as they are shown without colour.
  lines.mapIt(it.text)

func cellsOf*(line: string): seq[string] =
  ## The cells of a line of a table (`core/ruled.nim`), without the spaces around them.
  line.split("│").mapIt(it.strip)

func plainText*(lines: seq[Line]): string =
  ## Lines as they are shown without colour, one to a line.
  lines.mapIt(it.text).join("\n")

func emphasised*(s: Span): bool =
  ## Whether the span is in the style `em` (inside another, or alone).
  s.styles.anyIt($it == "em")
