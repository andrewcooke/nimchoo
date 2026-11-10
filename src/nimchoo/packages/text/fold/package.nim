## Comparing text without regard to case or accents.
##
## One function does it everywhere: `foldText` in the program, and the SQL function `fold()` that the database registers on
## every connection, so a name compared in a query is compared as it is in code.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])
