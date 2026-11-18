## What the tests ask of a span's styles.
import std/sequtils
import nimchoo/packages/ui/style

func styleOf*(s: Span): string =
  ## The innermost style of the span ("" for plain text).
  if s.styles.len == 0:
    ""
  else:
    $s.styles[^1]

func emphasised*(s: Span): bool =
  ## Whether the span is in the style `em` (inside another, or alone).
  s.styles.anyIt($it == "em")
