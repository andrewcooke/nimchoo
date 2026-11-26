## How the program looks: the rules of everything a person reads, and the helpers that keep them.
##
## The look is a few rules, each kept in one place (a helper, and where it can be checked, a test that refuses the next
## exception).  A new command follows them by using the helpers; it does not make its own.
##
## **Styles** (`style`, `core/line.nim`, `core/theme.nim`).  Nine, each for one thing, named in `core/line.baseStyles`
## (a name in the code is checked when it is compiled; a test checks that the built-in themes define them all):
##
## * `default`: around everything a command writes (`g.say()`, `g.show()`).
## * `em`: what to read first: a title, a heading.
## * `hide`: the bookkeeping, what was not recorded (`-`), and the lines of a table or a tree (`│ ─ ┼ └`, wherever they
##   are: `theme.lineStyle`).
## * `select`: the selection, and nothing else (`selectedStyle`): its rows, its days, the count of a list that is it.
## * `good`, `bad`, `warn`: what happened (done; failed or deleted; advisory), one table of words and their styles
##   (`vocabulary`), so that "failed" is `bad` wherever it appears.
## * `code`: literal text: a command, an option, a name in the program; what is between backticks, wherever it is
##   (drawn without them in colour: `line.codeStyle`; a test, `test_backticks`, refuses an option outside them).
## * `file`: the path of a file or a directory.
## * `tag`: a tag (`tags`).  Reverse video and no colour of its own, so that the style around it shows through: a tag in
##   a selected row is reverse video in the selection's colour (styles stack, each giving only what it changes).
##
## What each looks like is the theme's (`dark.theme` and `light.theme` here; the author's in the cache's
## `system/themes/`): a style gives only what it changes, `NAME.fg` and `v(COLOUR, GAMMA)` make a colour from one above, and every style
## has an alt version, `alt-X`, defined as X unless the theme says otherwise.  Styled text in the code is `span(text,
## "bad")` or markup, `~"<good imported> {n} files"` (`core/markup`: read when compiled; the values plain text).  `tools/look.nim`
## shows a theme.  (The web pages' colours are their own, in their templates.)
##
## **Messages** (`core/globals.nim`).  Three kinds, each one line, wrapped to the window:
##
## * a failure, `failure()`: "nch CMD: ..." all in `bad`, on stderr, and the command stops;
## * a warning, `g.warn()`: "warning: ..." all in `warn`, on stderr: something went wrong or the result is incomplete,
##   and the work went on;
## * what was done, `g.done()`: "done: ..." plain, on stdout, what it counts in the style that says what it is.
##
## A warning or a failure is one colour: what is between backticks in it is not in `code` (`theme.messageStyles`).  There
## are no notes: what is not a problem is not said (a setting is `nch --config`'s).  A test refuses "warning: " and
## "done: " written anywhere but the helpers, and a package naming another's command in its messages.
##
## **Counts and lists** (`units`).  A count has commas from 1,000 and says what it counts, singular for one:
## `counted(1113, "activity", "activities")` is "1,113 activities", `count(n)` the number alone (a test refuses commas
## written elsewhere).  A list of names is separated by commas.  The last line of a list is "done: N of TOTAL things",
## the count in `select` when what is listed is the selection (`vocabulary.countSpan`).
##
## **Numbers with units** (`units`, `interval`).  The unit follows the number with no space (`36.7km`, `+89m`, `17.8%`);
## a value that is not recorded is a dash.  Intervals in `d h m s`, no leading zero unit, the first unpadded and later ones
## two digits (`45s`, `22m05s`, `4h41m`, `2d03h07m`); seconds only under an hour.  A table column carries its unit in its
## header.  What a person types is read back by `units.parseDistance` (`1.5km`, `100m`) and `parseTimeSpan` (`60s`, `2h30m`),
## which want the unit and a finite number above zero (`Distance` in metres, `TimeSpan` in seconds; `m` is metres in a
## distance and minutes in a duration: the option's kind says which).
##
## **Tables** (`core/ruled.nim`).  Every table: lines between the columns, a rule under the headings, the last column
## wrapped to the window, and every other row in the alt styles unless the table says otherwise (the selection's tables
## and those of the help).  A test refuses columns lined up any other way.
##
## **Without colour** (a pipe, `NO_COLOR`).  Nothing is lost: a selected thing is in brackets, with a space where the
## bracket would be otherwise (`core/line.bracketed`), and what is between backticks keeps them.
##
## **Help** (`util/args/usage.nim`).  Every usage in one order (`usageOf`): the synopsis ("usage:" in `em`, the command
## lines in `code`), the introduction, the options (made from their descriptions: `util/args`), the notes, then sections
## under their headings, in `em`, lower case, with a colon ("commands:").
##
## The live display (`live`) redraws a block of lines in place on a terminal, and says how wide the output may be
## (`helpWidth()`, 120 when piped).

import ../../core/manifest

const package* = Package(depends: @[], fragments: @[])
