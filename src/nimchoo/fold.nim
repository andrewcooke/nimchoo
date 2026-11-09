## Comparing text without regard to case or accents.  One function does it everywhere: `foldText` in the program, and
## `fold()` in SQL (db/functions.nim registers the same function in every connection), so a name compared in a query
## and a name compared in the program are compared the same way.  SQLite's own `lower()` and `like` know only the ASCII
## letters.  "El Arrayán" -> "el arrayan".  Letters outside the table (other scripts) are lower-cased only.  Pure.
##
## To find text in a column: `instr(fold(column), ?) > 0` with `foldText(typed)` bound; to compare: `fold(a) = fold(b)`.

import std/[strutils, unicode]

{.push raises: [].}

const accented = [
  ('a', "àáâãäåāăą"),
  ('c', "çćĉčċ"),
  ('d', "ďđ"),
  ('e', "èéêëēĕėęě"),
  ('g', "ğĝġģ"),
  ('i', "ìíîïĩīĭįı"),
  ('l', "łľĺļ"),
  ('n', "ñńņň"),
  ('o', "òóôõöøōŏő"),
  ('r', "ŕřŗ"),
  ('s', "śŝşšș"),
  ('t', "ţťț"),
  ('u', "ùúûüũūŭůűų"),
  ('y', "ýÿ"),
  ('z', "źżž"),
]

func baseOf(r: Rune): char =
  ## The plain lower-case letter of a letter with or without accents or capital ('É' -> 'e'); '\0' for anything else.
  let lower = toLower(r)
  if int(lower) >= int('a') and int(lower) <= int('z'):
    return char(int(lower))
  for (base, letters) in accented:
    let forms = letters # (a copy: `runes` on a constant string crashes in this Nim)
    for f in forms.runes:
      if f == lower:
        return base
  '\0'

func foldText*(text: string): string =
  ## The text in lower case without accents ("El Arrayán" -> "el arrayan").  Blanks are kept: strip first if they
  ## should not count.
  for r in text.runes:
    let base = baseOf(r)
    if base != '\0':
      result.add base
    else:
      result.add $toLower(r)
