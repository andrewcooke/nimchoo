## How the program looks: units, intervals, styles and themes, tables and the live display.
##
## * The number formats every listing needs (`units`): the unit follows the number with no space (`36.7km`, `+89m`, `17.8%`,
##   `1h41m`), and a value that is not recorded is a dash.
## * Intervals of time (`interval`): units `d h m s`, no leading zero unit, the first unpadded and later ones two digits
##   (`45s`, `22m05s`, `4h41m`, `2d03h07m`); seconds only under an hour; rounding carries.
## * Styles (`style`, `vocabulary`, `markup`): text is in named styles, and what each looks like is the theme's
##   (`core/theme.nim`: foreground, background, weight, underline, italic, reverse, each optional; the built-in `dark.theme`
##   and `light.theme` are here).  The names the program uses are one list, `core/line.baseStyles`, checked when it is
##   compiled; a test checks that the built-in themes define them all.  Each is for one thing: `good` (done), `bad` (failed
##   or deleted), `warn` (advisory), `select` (the selection, `selectedStyle`), `em` (what to read first), `hide` (the
##   bookkeeping, what was not recorded, and the lines of a table or a tree, `│ ─ ┼ └`, wherever they are:
##   `theme.lineStyle`), `code` (literal text: a command, an option, the name of a package, an extension point or a
##   table; what is between backticks, wherever it is, drawn without them in colour: `theme.typedStyle`) and `file` (the
##   path of a file or a directory); `default` is around everything (all that a command writes is in it: `g.say()`,
##   `g.show()`).  Every style has an alt version, `alt-X`, for every other row of a table: the theme defines it as X
##   unless it says otherwise.  The words and styles for what happened are in `vocabulary`, one table, so that "failed"
##   is `bad` wherever it appears.  Markup (`<good imported> 3 files`; in the code `styled"..."`, read when compiled,
##   the values plain text) gives text its styles, which nest; `tools/look.nim` shows text with a theme.  (The web
##   pages' colours are their own, in their templates: they are always on white, whatever the terminal's theme.)
## * A block of lines redrawn in place on a terminal (`live`), which also says how wide the output may be (`helpWidth()`).
##   Every table is `core/ruled.nim`: lines between the columns, a rule under the headings, the last column wrapped.

import ../../core/manifest

const package* = Package(depends: @[], fragments: @[])
