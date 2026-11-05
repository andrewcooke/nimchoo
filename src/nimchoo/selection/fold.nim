## Matching text without regard to case or accents, in SQL.  SQLite's `like` ignores case only for plain letters and
## knows nothing of accents, so the typed text becomes a `glob` pattern in which each letter is a class of its forms:
## "arrayan" -> `*[aAàáâ...]rr[aAàá...]y...*`, which matches "El Arrayán".  The same pattern is made from "Arrayán" or
## "ARRAYAN".  Letters outside the table (other scripts) are matched as typed.  Pure.

import std/[strutils, unicode]

{.push raises: [].}

const accented = [
  ('a', "àáâãäåāăą"), ('c', "çćĉčċ"), ('d', "ďđ"), ('e', "èéêëēĕėęě"), ('g', "ğĝġģ"), ('i', "ìíîïĩīĭįı"),
  ('l', "łľĺļ"), ('n', "ñńņň"), ('o', "òóôõöøōŏő"), ('r', "ŕřŗ"), ('s', "śŝşšș"), ('t', "ţťț"),
  ('u', "ùúûüũūŭůűų"), ('y', "ýÿ"), ('z', "źżž")]

func baseOf(r: Rune): char =
  ## The plain lower-case letter of a letter with or without accents or capital ('É' -> 'e'); '\0' for anything else.
  let lower = toLower(r)
  if int(lower) >= int('a') and int(lower) <= int('z'): return char(int(lower))
  for (base, letters) in accented:
    let forms = letters                 # (a copy: `runes` on a constant string crashes in this Nim)
    for f in forms.runes:
      if f == lower: return base
  '\0'

func classOf(base: char): string =
  ## "[aAàÀáÁ...]": every form of the letter.
  result = "[" & $base & $toUpper(Rune(base))
  for (b, letters) in accented:
    if b == base:
      let forms = letters
      for f in forms.runes: result.add $f & $toUpper(f)
  result.add "]"

func foldGlob*(text: string): string =
  ## A `glob` pattern that finds `text` anywhere in a value, whatever its case and accents.
  result = "*"
  for r in text.strip.runes:
    let base = baseOf(r)
    if base != '\0': result.add classOf(base)
    else:
      case r
      of Rune('*'): result.add "[*]"
      of Rune('?'): result.add "[?]"
      of Rune('['): result.add "[[]"
      else: result.add $r
  result.add "*"
