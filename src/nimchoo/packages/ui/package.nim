## How the program looks: units, intervals, colours, tables and the live display.
##
## * The number formats every listing needs (`units`): the unit follows the number with no space (`36.7km`, `+89m`, `17.8%`,
##   `1h41m`), and a value that is not recorded is a dash.
## * Intervals of time (`interval`): units `d h m s`, no leading zero unit, the first unpadded and later ones two digits
##   (`45s`, `22m05s`, `4h41m`, `2d03h07m`); seconds only under an hour; rounding carries.
## * Colours (`palette`, `style`, `vocabulary`): the words and looks for what happened are in `vocabulary`, one table, so that
##   "failed" is red wherever it appears.  Colour only where it means something; the status colours are green (done), red
##   (failed or deleted), yellow (advisory) and blue (the selection, `selectedColour`), and are used for nothing else.
## * A table's cells lined up in columns (`columns`), and a block of lines redrawn in place on a terminal (`live`), which also
##   says how wide the help text may be (`helpWidth`).

import ../../core/manifest

const package* = Package(depends: @[], fragments: @[])
