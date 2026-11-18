## What styled text looks like with a theme (a tool for trying themes: no part of nch).
##
##     nim c -d:release --hints:off -o:build/look tools/look.nim
##     build/look ~/.cache/nch/system/themes/dark.txt '[good imported] 3 files [hide (1.2s)]'
##     build/look THEME                  # a sample: every style of the theme, nested, and lines like those of nch
##     build/look THEME - < lines.txt    # each line of stdin (read as markup)
##     build/look --plain THEME ...      # without colour, as NO_COLOR would show it
##
## The markup is that of `ui/markup.nim`: `[NAME text]`, nesting, `\[` `\]` `\\`.  Each TEXT given is a line; a `\n` in one
## (as two characters, typed in the shell) is a newline too, so that a style running over lines can be tried.

import std/[options, os, sequtils, strformat, strutils, tables]
import nimchoo/core/errors
import nimchoo/core/theme
import nimchoo/packages/cache/cache
import nimchoo/packages/themes/choose
import nimchoo/packages/ui/[markup, style]

const examples = [
  "[good imported] 3 files [hide (1.2s)]",
  "[bad failed] ride.fit: [em not a FIT file] (it ends at byte 12)",
  "[warn note:] the clock of ride.fit jumped back 3m, so the times after it are moved",
  "   id  date        name                  distance",
  "[select   737  2026-11-17  Camino a Farellones     36.7km]",
  "  738  2026-11-18  San Cristóbal            8.4km",
  "[select   739  2026-11-18  Pocuro                       [hide —]]",
  "[select a selected line with [default a plain word] in it]",
  "[em a heading [hide with a quiet aside] and more]",
  "[hide a style that runs\nover a newline]",
]

proc sample(t: Theme): seq[string] =
  ## Every style alone, inside the others that change the colour, and lines like those of nch.
  let names = toSeq(t.styles.keys)
  let width = max(names.mapIt(it.len)) + 2
  result.add "each style alone, then inside each other style:"
  for name in names:
    var line = fmt"  [{name} {name.alignLeft(width)}]"
    for outer in names:
      if outer != name:
        line.add fmt" [{outer} [{name} {name}]]"
    result.add line
  result.add ""
  result.add "lines like those of nch:"
  for e in examples:
    result.add e

proc show(t: Theme, text: string, colour: bool) =
  try:
    for line in styled(Paint(theme: t, colour: colour), text):
      echo line
  except MarkupError as e:
    echo fmt"({e.msg}) {text}"

proc whereThemesAre(): string =
  ## Where the themes are, to say with a usage or a file that cannot be read.
  let cache = cacheDir()
  result = "the built-in themes are in src/nimchoo/packages/ui/ (dark.txt, light.txt)"
  if cache.isSome:
    let names = themeNames(cache.get).mapIt(it & ".txt").join(", ")
    result.add fmt"; nch uses those in {themesDir(cache.get)} ({names})"

proc main() =
  var args = commandLineParams()
  let colour = "--plain" notin args
  args = args.filterIt(it != "--plain")
  if args.len == 0:
    quit "usage: look [--plain] THEME [TEXT... | -]\n(" & whereThemesAre() & ")", 2
  var t: Theme
  try:
    t = parseTheme(readFile(args[0]))
  except IOError as e:
    quit fmt"look: cannot read {args[0]}: {e.msg}" & "\n(" & whereThemesAre() & ")", 1
  except ThemeError as e:
    quit fmt"look: {args[0]}: {e.msg}", 1
  let texts = args[1 ..^ 1]
  if texts.len > 0:
    for text in texts:
      if text == "-":
        for l in stdin.lines:
          show(t, l, colour)
      else:
        show(t, text.replace("\\n", "\n"), colour)
  else:
    for text in sample(t):
      show(t, text, colour)

main()
