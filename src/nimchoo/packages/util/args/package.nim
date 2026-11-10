## One command-line parser for all the commands, and the usage text made from the same descriptions.
##
## A command describes its options as a list (`Opt`: the names, whether there is a value, what to do with it) and
## `parseOptions` does the walking.  An option also describes itself (`OptDoc`: names, the placeholder for its value, help,
## how many words it takes, what could complete it), added with `.documented`; the option list of a command's usage is made
## from the descriptions (`usage.nim`), wrapped to the width of the terminal (`ui/live.helpWidth`), so it cannot differ from
## what the parser accepts.  A package that offers an option to another command (the criteria of `activities`) hands over
## just the description.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])
