## One command-line parser for all the commands, and the usage text made from the same descriptions.
##
## A command describes its options as a list (`Opt`s made with `flag`, `text`, `number`, `whole`, `custom` and
## `listOption`).  Each option carries its description, which the compiler requires: its names, the placeholder for its
## value, its help, whether it is indented under the option before it (`level`: `--rename` under `--edit`), and what could
## complete it (`OptDoc`).  The option list of a command's usage is made from the descriptions (`usage.nim`), wrapped to the
## width of the terminal (`ui/live.helpWidth`), so it cannot differ from what the parser accepts; only the synopsis, the
## introduction and the notes are written by hand.  A package that offers an option to another command (the criteria of
## `activities`) hands over just the description.
##
## `parseCommand` reads the options into a builder and the command's own `finish` turns it into the answer: a `Parsed[T]`,
## which is valid parameters (a variant on the action, so that a combination of options that means nothing cannot be
## represented), a request for help, or a problem (a sentence that does not name the option).  An option's `apply` returns
## `fine` or `refuse("...")`.  An option may also say it is allowed in an address of the local web server (`address`, with
## a check for its value); the server's list of what a page may be given is made from the options themselves.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])
