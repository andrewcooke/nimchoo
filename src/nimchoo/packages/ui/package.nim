## How the program looks: units, intervals, styles and themes, tables and the live display.
##
## * The number formats every listing needs (`units`): the unit follows the number with no space (`36.7km`, `+89m`, `17.8%`,
##   `1h41m`), and a value that is not recorded is a dash.
## * Intervals of time (`interval`): units `d h m s`, no leading zero unit, the first unpadded and later ones two digits
##   (`45s`, `22m05s`, `4h41m`, `2d03h07m`); seconds only under an hour; rounding carries.
## * Styles (`style`, `vocabulary`, `markup`): text is in named styles, and what each looks like is the theme's
##   (`core/theme.nim`: foreground, background, weight, underline, italic, reverse, each optional; the built-in `dark.txt`
##   and `light.txt` are here, and the names the program uses are those of `dark.txt`, checked when it is compiled).  The
##   words and styles for what happened are in `vocabulary`, one table, so that "failed" is `bad` wherever it appears.
##   Style only where it means something: `good` (done), `bad` (failed or deleted), `warn` (advisory), `select` (the
##   selection, `selectedStyle`), each used for nothing else; `em` for what to read first, `hide` for the bookkeeping and
##   what was not recorded; `default` is around everything (all that a command writes is in it: `g.say`, `g.show`).  Markup
##   (`[good imported] 3 files`; in the code `styled"..."`, read when compiled, the values plain text) gives text its styles,
##   which nest; `tools/look.nim` shows text with a theme.  (The web pages' colours are still `palette`'s: TODO "Styles,
##   themes and markup", step 5.)
## * A table's cells lined up in columns (`columns`), and a block of lines redrawn in place on a terminal (`live`), which also
##   says how wide the help text may be (`helpWidth`).

import ../../core/manifest

const package* = Package(depends: @[], fragments: @[])
